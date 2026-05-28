import SwiftUI

struct MainView: View {
    @StateObject private var controller = ServiceController.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsPanel
                    providersPanel
                    logsPanel
                }
                .padding(22)
            }
        }
        .frame(minWidth: 780, minHeight: 680)
        .onAppear { controller.refreshPortOwner() }
        .onChange(of: controller.settings.listenAddr) { _ in controller.refreshPortOwner() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Moon Bridge")
                    .font(.system(size: 24, weight: .semibold))
                HStack(spacing: 8) {
                    StatusPill(state: controller.state)
                    Text(controller.serviceURL)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { controller.saveSettings() } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)

            Button { controller.openSupportFolder() } label: {
                Label("目录", systemImage: "folder")
            }

            Button { controller.openConfigFile() } label: {
                Label("配置文件", systemImage: "doc.text")
            }

            if controller.state.isRunning {
                Button(role: .destructive) { controller.stop() } label: {
                    Label("关闭服务", systemImage: "stop.fill")
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button { controller.start() } label: {
                    Label("启动服务", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Settings

    private var settingsPanel: some View {
        SectionPanel(title: "本地服务", subtitle: controller.message) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    FieldLabel("监听地址")
                    TextField("127.0.0.1:38440", text: $controller.settings.listenAddr)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    FieldLabel("默认别名")
                    TextField("moonbridge", text: $controller.settings.routeAlias)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    FieldLabel("最大输出")
                    TextField("65536", text: $controller.settings.maxTokens)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    FieldLabel("系统提示")
                    TextEditor(text: $controller.settings.systemPrompt)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 80)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor))
                        )
                }
            }
        }
    }

    // MARK: - Providers

    private var providersPanel: some View {
        SectionPanel(
            title: "服务商",
            subtitle: "\(controller.settings.providers.count) 个已配置"
        ) {
            VStack(spacing: 8) {
                ForEach($controller.settings.providers) { $provider in
                    ProviderCard(
                        provider: $provider,
                        isActive: provider.id == controller.settings.activeProviderID,
                        onActivate: { controller.settings.activeProviderID = provider.id },
                        onDelete: { controller.deleteProvider(provider.id) },
                        canDelete: controller.settings.providers.count > 1
                    )
                }

                Button { controller.addProvider() } label: {
                    Label("添加服务商", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 6)

                if controller.settings.providers.count > 1 {
                    Divider()
                    HStack(spacing: 10) {
                        Text("视觉能力")
                            .foregroundStyle(.secondary)
                            .frame(width: 82, alignment: .trailing)

                        Picker("", selection: Binding<UUID?>(
                            get: { controller.settings.visualProviderID },
                            set: { controller.settings.visualProviderID = $0 }
                        )) {
                            Text("不使用").tag(nil as UUID?)
                            ForEach(controller.settings.providers) { p in
                                Text(p.name).tag(p.id as UUID?)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 180)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Logs

    private var logsPanel: some View {
        SectionPanel(title: "运行日志", subtitle: "启动失败时先看这里") {
            ScrollView {
                Text(controller.logs.isEmpty ? "暂无日志" : controller.logs)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(controller.logs.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 120, maxHeight: 180)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor))
            )
        }
    }
}

// MARK: - Provider Card

struct ProviderCard: View {
    @Binding var provider: ProviderSettings
    let isActive: Bool
    let onActivate: () -> Void
    let onDelete: () -> Void
    let canDelete: Bool

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header row — tapping the chevron toggles expansion
            HStack(spacing: 8) {
                Button(action: onActivate) {
                    Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(isActive ? "当前默认服务商" : "设为默认")

                TextField("名称", text: $provider.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 100)

                Text(provider.baseURL.trimmed)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("删除此服务商")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "收起" : "展开详情")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if isExpanded {
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        FieldLabel("接口地址")
                        TextField("https://api.example.com/anthropic", text: $provider.baseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        FieldLabel("API Key")
                        SecureField("sk-...", text: $provider.apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        FieldLabel("模型名")
                        TextField("model-name", text: $provider.model)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        FieldLabel("上下文")
                        TextField("128000", text: $provider.contextWindow)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        FieldLabel("模型输出")
                        TextField("65536", text: $provider.maxOutputTokens)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        FieldLabel("协议版本")
                        TextField("2023-06-01", text: $provider.version)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    isActive ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor),
                    lineWidth: isActive ? 1.5 : 1
                )
        )
    }
}

// MARK: - Shared Components

struct SectionPanel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            content
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor))
        )
    }
}

struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 82, alignment: .trailing)
    }
}

struct StatusPill: View {
    let state: ServiceState

    var body: some View {
        Label(state.label, systemImage: iconName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var iconName: String {
        switch state {
        case .running, .externalRunning: return "checkmark.circle.fill"
        case .starting, .stopping: return "clock.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .stopped: return "circle"
        }
    }

    private var color: Color {
        switch state {
        case .running, .externalRunning: return .green
        case .starting, .stopping: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        }
    }
}
