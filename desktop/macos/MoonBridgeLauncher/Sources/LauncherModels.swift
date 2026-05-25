import Foundation

struct LauncherSettings: Codable, Equatable {
    var listenAddr: String = "127.0.0.1:38440"
    var routeAlias: String = "moonbridge"
    var maxTokens: String = "4096"
    var primaryProvider: ProviderSettings = ProviderSettings(
        name: "deepseek",
        baseURL: "https://api.deepseek.com/anthropic",
        apiKey: "",
        version: "2023-06-01",
        model: "deepseek-v4-pro"
    )
    var visualProvider: ProviderSettings = ProviderSettings(
        name: "kimi",
        baseURL: "https://api.moonshot.ai/anthropic",
        apiKey: "",
        version: "2023-06-01",
        model: "kimi-for-coding"
    )
    var enableVisualProvider: Bool = false
}

struct ProviderSettings: Codable, Equatable {
    var name: String
    var baseURL: String
    var apiKey: String
    var version: String
    var model: String
}

struct PortOwner: Equatable {
    var pid: Int32
    var command: String

    var isMoonBridge: Bool {
        command.lowercased().contains("moonbridge") || command.lowercased().contains("moonbridg")
    }
}

enum ServiceState: Equatable {
    case stopped
    case starting
    case running(pid: Int32)
    case externalRunning(pid: Int32)
    case stopping
    case failed(String)

    var label: String {
        switch self {
        case .stopped:
            return "未启动"
        case .starting:
            return "启动中"
        case .running, .externalRunning:
            return "运行中"
        case .stopping:
            return "关闭中"
        case .failed:
            return "启动失败"
        }
    }

    var isRunning: Bool {
        if case .running = self {
            return true
        }
        if case .externalRunning = self {
            return true
        }
        return false
    }

    var pid: Int32? {
        switch self {
        case .running(let pid), .externalRunning(let pid):
            return pid
        default:
            return nil
        }
    }
}

enum LauncherError: LocalizedError {
    case serviceBinaryMissing
    case invalidConfig(String)

    var errorDescription: String? {
        switch self {
        case .serviceBinaryMissing:
            return "安装包里缺少 moonbridge 服务文件。"
        case .invalidConfig(let message):
            return message
        }
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension URL {
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ProviderSettings {
    var normalized: ProviderSettings {
        ProviderSettings(
            name: name.trimmed,
            baseURL: baseURL.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            apiKey: apiKey.trimmed,
            version: version.trimmed.isEmpty ? "2023-06-01" : version.trimmed,
            model: model.trimmed
        )
    }
}

func yamlKey(_ value: String) -> String {
    yamlString(value.trimmed)
}

func yamlString(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
}
