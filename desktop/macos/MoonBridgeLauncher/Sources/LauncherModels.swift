import Foundation

struct LauncherSettings: Codable, Equatable {
    var listenAddr: String = "127.0.0.1:38440"
    var routeAlias: String = "moonbridge"
    var maxTokens: String = "65536"
    var systemPrompt: String = "[System Reminder]: Please pay close attention to the system instructions, AGENTS.md files, and any other context provided. Follow them carefully and completely in your response.\n[User]:"
    var providers: [ProviderSettings] = [
        ProviderSettings(
            id: ProviderSettings.defaultDeepSeekID,
            name: "deepseek",
            baseURL: "https://api.deepseek.com/anthropic",
            apiKey: "",
            version: "2023-06-01",
            model: "deepseek-v4-pro",
            contextWindow: "1000000",
            maxOutputTokens: "384000"
        )
    ]
    var activeProviderID: UUID = ProviderSettings.defaultDeepSeekID
    var visualProviderID: UUID? = nil

    // MARK: Codable — 兼容旧版 primaryProvider / visualProvider
    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        listenAddr = try container.decodeIfPresent(String.self, forKey: .listenAddr) ?? "127.0.0.1:38440"
        routeAlias = try container.decodeIfPresent(String.self, forKey: .routeAlias) ?? "moonbridge"
        maxTokens = try container.decodeIfPresent(String.self, forKey: .maxTokens) ?? "65536"
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? "[System Reminder]: Please pay close attention to the system instructions, AGENTS.md files, and any other context provided. Follow them carefully and completely in your response.\n[User]:"

        if let newProviders = try container.decodeIfPresent([ProviderSettings].self, forKey: .providers), !newProviders.isEmpty {
            providers = newProviders
            activeProviderID = try container.decodeIfPresent(UUID.self, forKey: .activeProviderID) ?? newProviders[0].id
            visualProviderID = try container.decodeIfPresent(UUID.self, forKey: .visualProviderID)
        } else {
            // 旧格式兼容：从 primaryProvider / visualProvider / activeProviderName 迁移
            let primary = try container.decodeIfPresent(ProviderSettings.self, forKey: .primaryProvider)
            let visual = try container.decodeIfPresent(ProviderSettings.self, forKey: .visualProvider)
            let enableVisual = try container.decodeIfPresent(Bool.self, forKey: .enableVisualProvider) ?? false

            var migrated: [ProviderSettings] = []
            if let p = primary {
                migrated.append(p)
                activeProviderID = p.id
            }
            if let v = visual, enableVisual, v.name != primary?.name {
                migrated.append(v)
                visualProviderID = v.id
            }
            providers = migrated.isEmpty ? [
                ProviderSettings(
                    id: ProviderSettings.defaultDeepSeekID,
                    name: "deepseek",
                    baseURL: "https://api.deepseek.com/anthropic",
                    apiKey: "",
                    version: "2023-06-01",
                    model: "deepseek-v4-pro",
                    contextWindow: "1000000",
                    maxOutputTokens: "384000"
                )
            ] : migrated

            // 如果新版有 activeProviderName（字符串），尝试按名称匹配到 UUID
            if activeProviderID == UUID() {
                if let oldName = try container.decodeIfPresent(String.self, forKey: .activeProviderName), !oldName.isEmpty {
                    if let match = providers.first(where: { $0.name == oldName }) {
                        activeProviderID = match.id
                    }
                }
                if activeProviderID == UUID() {
                    activeProviderID = providers[0].id
                }
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(listenAddr, forKey: .listenAddr)
        try container.encode(routeAlias, forKey: .routeAlias)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encode(systemPrompt, forKey: .systemPrompt)
        try container.encode(providers, forKey: .providers)
        try container.encode(activeProviderID, forKey: .activeProviderID)
        try container.encodeIfPresent(visualProviderID, forKey: .visualProviderID)
    }

    private enum CodingKeys: String, CodingKey {
        case listenAddr, routeAlias, maxTokens
        case systemPrompt
        case providers, activeProviderID, visualProviderID
        case activeProviderName, primaryProvider, visualProvider, enableVisualProvider
    }

    var activeProvider: ProviderSettings {
        providers.first { $0.id == activeProviderID } ?? providers[0]
    }

    var activeProviderName: String { activeProvider.name }

    var visualProvider: ProviderSettings? {
        guard let vid = visualProviderID else { return nil }
        return providers.first { $0.id == vid }
    }

    var visualProviderName: String {
        visualProvider?.name ?? ""
    }
}

struct ProviderSettings: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var baseURL: String
    var apiKey: String
    var version: String
    var model: String
    var contextWindow: String
    var maxOutputTokens: String

    static let defaultDeepSeekID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        apiKey: String,
        version: String,
        model: String,
        contextWindow: String? = nil,
        maxOutputTokens: String? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.version = version
        self.model = model
        self.contextWindow = contextWindow ?? Self.defaultContextWindow(baseURL: baseURL, model: model)
        self.maxOutputTokens = maxOutputTokens ?? Self.defaultMaxOutputTokens(baseURL: baseURL, model: model)
    }

    // 旧格式解码（没有 UUID）时自动生成
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "2023-06-01"
        model = try container.decode(String.self, forKey: .model)
        contextWindow = try container.decodeIfPresent(String.self, forKey: .contextWindow)
            ?? Self.defaultContextWindow(baseURL: baseURL, model: model)
        maxOutputTokens = try container.decodeIfPresent(String.self, forKey: .maxOutputTokens)
            ?? Self.defaultMaxOutputTokens(baseURL: baseURL, model: model)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKey, version, model, contextWindow, maxOutputTokens
    }

    private static func defaultContextWindow(baseURL: String, model: String) -> String {
        let marker = "\(baseURL) \(model)".lowercased()
        if marker.contains("deepseek") { return "1000000" }
        if marker.contains("kimi") || marker.contains("moonshot") { return "128000" }
        return "200000"
    }

    private static func defaultMaxOutputTokens(baseURL: String, model: String) -> String {
        let marker = "\(baseURL) \(model)".lowercased()
        if marker.contains("deepseek") { return "384000" }
        return "65536"
    }
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
        case .stopped: return "未启动"
        case .starting: return "启动中"
        case .running, .externalRunning: return "运行中"
        case .stopping: return "关闭中"
        case .failed: return "启动失败"
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        if case .externalRunning = self { return true }
        return false
    }

    var pid: Int32? {
        switch self {
        case .running(let pid), .externalRunning(let pid): return pid
        default: return nil
        }
    }
}

enum LauncherError: LocalizedError {
    case serviceBinaryMissing
    case invalidConfig(String)

    var errorDescription: String? {
        switch self {
        case .serviceBinaryMissing: return "安装包里缺少 moonbridge 服务文件。"
        case .invalidConfig(let message): return message
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
    var fileExists: Bool { FileManager.default.fileExists(atPath: path) }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension ProviderSettings {
    var normalized: ProviderSettings {
        ProviderSettings(
            name: name.trimmed,
            baseURL: baseURL.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            apiKey: apiKey.trimmed,
            version: version.trimmed.isEmpty ? "2023-06-01" : version.trimmed,
            model: model.trimmed,
            contextWindow: contextWindow.trimmed,
            maxOutputTokens: maxOutputTokens.trimmed
        )
    }
}

func yamlKey(_ value: String) -> String { yamlString(value.trimmed) }

func yamlString(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
}
