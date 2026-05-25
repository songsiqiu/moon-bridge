import AppKit
import Darwin
import Foundation
import SwiftUI

@MainActor
final class ServiceController: ObservableObject {
    static let shared = ServiceController()

    @Published var settings: LauncherSettings
    @Published var state: ServiceState = .stopped
    @Published var message: String = ""
    @Published var logs: String = ""

    let supportDir: URL
    let configURL: URL
    let settingsURL: URL
    let logURL: URL

    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var externalProcessID: Int32?

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        supportDir = base.appendingPathComponent("MoonBridge", isDirectory: true)
        configURL = supportDir.appendingPathComponent("config.yml")
        settingsURL = supportDir.appendingPathComponent("launcher-settings.json")
        logURL = supportDir.appendingPathComponent("moonbridge.log")
        settings = Self.loadSettings(from: settingsURL)
        prepareSupportFiles()
        refreshPortOwner()
    }

    var serviceURL: String {
        "http://\(effectiveListenAddr)"
    }

    private var effectiveListenAddr: String {
        let addr = settings.listenAddr.trimmed
        return addr.isEmpty ? "127.0.0.1:38440" : addr
    }

    func saveSettings() {
        do {
            try prepareSupportFilesThrowing()
            let data = try JSONEncoder.pretty.encode(settings)
            try data.write(to: settingsURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
            try renderedConfig().write(to: configURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
            message = state.isRunning ? "配置已保存，重启服务后生效。" : "配置已保存。"
        } catch {
            message = "保存失败：\(error.localizedDescription)"
        }
    }

    func start() {
        guard !state.isRunning else {
            return
        }

        do {
            try validateSettings()
            if let owner = portOwner(for: effectiveListenAddr) {
                if owner.isMoonBridge {
                    externalProcessID = owner.pid
                    state = .externalRunning(pid: owner.pid)
                    message = "已有 Moon Bridge 服务在运行，可直接关闭。"
                    appendLog("检测到已有 Moon Bridge 服务占用 \(effectiveListenAddr)，PID \(owner.pid)。\n")
                    return
                }
                throw LauncherError.invalidConfig("监听地址已被其他程序占用，PID \(owner.pid)。")
            }

            try prepareSupportFilesThrowing()
            try renderedConfig().write(to: configURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
            try JSONEncoder.pretty.encode(settings).write(to: settingsURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
            try "".write(to: logURL, atomically: true, encoding: .utf8)

            let serviceBinary = try bundledServiceBinary()
            let task = Process()
            task.executableURL = serviceBinary
            task.currentDirectoryURL = supportDir
            task.arguments = ["-config", configURL.path]

            let stdout = Pipe()
            let stderr = Pipe()
            task.standardOutput = stdout
            task.standardError = stderr

            attachLogPipe(stdout.fileHandleForReading)
            attachLogPipe(stderr.fileHandleForReading)

            state = .starting
            message = "正在启动服务..."

            task.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    self.detachLogPipes()
                    self.process = nil
                    if case .stopping = self.state {
                        self.state = .stopped
                        self.message = "服务已关闭。"
                    } else if proc.terminationStatus == 0 {
                        self.state = .stopped
                        self.message = "服务已停止。"
                    } else {
                        self.state = .failed("服务退出，代码 \(proc.terminationStatus)。")
                        self.message = "服务已退出，查看下方日志。"
                    }
                }
            }

            try task.run()
            process = task
            stdoutHandle = stdout.fileHandleForReading
            stderrHandle = stderr.fileHandleForReading

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 550_000_000)
                if self.process === task && task.isRunning {
                    self.state = .running(pid: task.processIdentifier)
                    self.message = "服务已启动：\(self.serviceURL)"
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
            message = "启动失败：\(error.localizedDescription)"
        }
    }

    func stop() {
        if let task = process {
            state = .stopping
            message = "正在关闭服务..."
            task.terminate()

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if task.isRunning {
                    kill(task.processIdentifier, SIGKILL)
                }
            }
            return
        }

        if let pid = externalProcessID ?? state.pid {
            state = .stopping
            message = "正在关闭已有服务..."
            terminateExternalMoonBridge(pid: pid)
            return
        }

        refreshPortOwner()
        guard state.isRunning else {
            state = .stopped
            message = "服务没有在运行。"
            return
        }
        stop()
    }

    func openConfigFile() {
        saveSettings()
        NSWorkspace.shared.open(configURL)
    }

    func openSupportFolder() {
        prepareSupportFiles()
        NSWorkspace.shared.open(supportDir)
    }

    func terminateOnQuit() {
        if let task = process, task.isRunning {
            task.terminate()
        }
    }

    func refreshPortOwner() {
        guard process == nil else {
            return
        }
        if let owner = portOwner(for: effectiveListenAddr), owner.isMoonBridge {
            externalProcessID = owner.pid
            state = .externalRunning(pid: owner.pid)
            message = "已有 Moon Bridge 服务在运行。"
        } else if case .externalRunning = state {
            externalProcessID = nil
            state = .stopped
            message = "服务没有在运行。"
        }
    }

    private static func loadSettings(from url: URL) -> LauncherSettings {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LauncherSettings.self, from: data)
        else {
            return LauncherSettings()
        }
        return decoded
    }

    private func prepareSupportFiles() {
        try? prepareSupportFilesThrowing()
        if !configURL.fileExists {
            try? renderedConfig().write(to: configURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        }
        if !settingsURL.fileExists {
            try? JSONEncoder.pretty.encode(settings).write(to: settingsURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
        }
    }

    private func prepareSupportFilesThrowing() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: supportDir.appendingPathComponent("data", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: supportDir.appendingPathComponent("trace", isDirectory: true), withIntermediateDirectories: true)
    }

    private func bundledServiceBinary() throws -> URL {
        if let url = Bundle.main.url(forResource: "moonbridge", withExtension: nil) {
            return url
        }
        throw LauncherError.serviceBinaryMissing
    }

    private func terminateExternalMoonBridge(pid: Int32) {
        guard let owner = portOwner(for: effectiveListenAddr), owner.pid == pid, owner.isMoonBridge else {
            externalProcessID = nil
            state = .stopped
            message = "服务没有在运行。"
            return
        }
        kill(pid, SIGTERM)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if let currentOwner = self.portOwner(for: self.effectiveListenAddr), currentOwner.pid == pid {
                kill(pid, SIGKILL)
            }
            self.externalProcessID = nil
            self.state = .stopped
            self.message = "服务已关闭。"
        }
    }

    private func portOwner(for address: String) -> PortOwner? {
        let parts = address.split(separator: ":", maxSplits: 1).map(String.init)
        guard let portText = parts.last, Int(portText) != nil else {
            return nil
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-nP", "-iTCP:\(portText)", "-sTCP:LISTEN", "-F", "pc"]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        var pid: Int32?
        var command = ""
        for line in raw.split(separator: "\n").map(String.init) {
            if line.hasPrefix("p") {
                pid = Int32(line.dropFirst())
            } else if line.hasPrefix("c") {
                command = String(line.dropFirst())
            }
        }
        guard let pid else {
            return nil
        }
        return PortOwner(pid: pid, command: command)
    }

    private func validateSettings() throws {
        if settings.listenAddr.trimmed.isEmpty {
            settings.listenAddr = "127.0.0.1:38440"
        }
        let address = effectiveListenAddr
        if !address.contains(":") {
            throw LauncherError.invalidConfig("本地监听地址需要类似 127.0.0.1:38440。")
        }
        if settings.routeAlias.trimmed.isEmpty {
            throw LauncherError.invalidConfig("默认模型别名不能为空。")
        }
        if Int(settings.maxTokens.trimmed) == nil {
            throw LauncherError.invalidConfig("最大输出 Tokens 必须是数字。")
        }
        try validateProvider(settings.primaryProvider, label: "主接口", requiresAPIKey: true)
        if settings.enableVisualProvider {
            try validateProvider(settings.visualProvider, label: "视觉接口", requiresAPIKey: true)
        }
    }

    private func validateProvider(_ provider: ProviderSettings, label: String, requiresAPIKey: Bool) throws {
        if provider.name.trimmed.isEmpty {
            throw LauncherError.invalidConfig("\(label)名称不能为空。")
        }
        if provider.baseURL.trimmed.isEmpty {
            throw LauncherError.invalidConfig("\(label)地址不能为空。")
        }
        if requiresAPIKey && provider.apiKey.trimmed.isEmpty {
            throw LauncherError.invalidConfig("\(label) Key 不能为空。")
        }
        if provider.model.trimmed.isEmpty {
            throw LauncherError.invalidConfig("\(label)模型名不能为空。")
        }
    }

    private func renderedConfig() -> String {
        let primary = settings.primaryProvider.normalized
        let visual = settings.visualProvider.normalized
        let visualEnabled = settings.enableVisualProvider
        let maxTokens = Int(settings.maxTokens.trimmed) ?? 4096
        let alias = settings.routeAlias.trimmed
        let visualProviderName = visualEnabled ? visual.name : primary.name
        let visualModelName = visualEnabled ? visual.model : primary.model

        var yaml = """
        mode: "Transform"

        log:
          level: "info"
          format: "text"

        server:
          addr: \(yamlString(settings.listenAddr.trimmed))

        persistence:
          active_provider: "db_sqlite"

        extensions:
          deepseek_v4:
            config:
              reinforce_instructions: true
          visual:
            config:
              provider: \(yamlString(visualProviderName))
              model: \(yamlString(visualModelName))
              max_rounds: 4
              max_tokens: 2048
          db_sqlite:
            enabled: true
            config:
              path: "./data/moonbridge.db"
              wal: true
              busy_timeout_ms: 5000
              max_open_conns: 1
          metrics:
            enabled: true
            config:
              default_limit: 100
              max_limit: 1000

        cache:
          mode: "explicit"
          ttl: "5m"
          prompt_caching: true
          automatic_prompt_cache: false
          explicit_cache_breakpoints: true
          allow_retention_downgrade: false
          max_breakpoints: 4
          min_cache_tokens: 1024
          expected_reuse: 2
          minimum_value_score: 2048
          min_breakpoint_tokens: 1024

        trace:
          enabled: false

        defaults:
          model: \(yamlString(alias))
          max_tokens: \(maxTokens)

        models:
          \(yamlKey(primary.model)):
            context_window: 1000000
            max_output_tokens: 384000
            display_name: \(yamlString(primary.model))
            default_reasoning_level: "high"
            supported_reasoning_levels:
              - effort: "high"
                description: "High reasoning effort"
              - effort: "xhigh"
                description: "Extra high reasoning effort"
            supports_reasoning_summaries: true
            default_reasoning_summary: "auto"
            extensions:
              deepseek_v4:
                enabled: true
              visual:
                enabled: \(visualEnabled ? "true" : "false")

        """

        if visualEnabled && visual.model != primary.model {
            yaml += """
              \(yamlKey(visual.model)):
                context_window: 128000
                max_output_tokens: 64000

            """
        }

        yaml += """
        providers:
          \(yamlKey(primary.name)):
            base_url: \(yamlString(primary.baseURL))
            api_key: \(yamlString(primary.apiKey))
            version: \(yamlString(primary.version))
            user_agent: "moonbridge/desktop"
            offers:
              - model: \(yamlString(primary.model))

        """

        if visualEnabled && visual.name == primary.name && visual.model != primary.model {
            yaml += "      - model: \(yamlString(visual.model))\n\n"
        }

        if visualEnabled && visual.name != primary.name {
            yaml += """
              \(yamlKey(visual.name)):
                base_url: \(yamlString(visual.baseURL))
                api_key: \(yamlString(visual.apiKey))
                version: \(yamlString(visual.version))
                user_agent: "moonbridge/desktop"
                offers:
                  - model: \(yamlString(visual.model))

            """
        }

        yaml += """
        routes:
          \(yamlKey(alias)):
            model: \(yamlString(primary.model))
            provider: \(yamlString(primary.name))

        """
        return yaml
    }

    private func attachLogPipe(_ handle: FileHandle) {
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else {
                return
            }
            Task { @MainActor in
                self?.appendLog(chunk)
            }
        }
    }

    private func detachLogPipes() {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        stdoutHandle = nil
        stderrHandle = nil
    }

    private func appendLog(_ chunk: String) {
        logs += chunk
        if logs.count > 20_000 {
            logs = String(logs.suffix(20_000))
        }
        if let data = chunk.data(using: .utf8) {
            if !logURL.fileExists {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        }
    }
}
