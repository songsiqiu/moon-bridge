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
                    providerPanel(
                        title: "主接口",
                        subtitle: "默认模型会走这里",
                        provider: $controller.settings.primaryProvider
                    )
                    Toggle("启用视觉接口", isOn: $controller.settings.enableVisualProvider)
                        .toggleStyle(.switch)
                    if controller.settings.enableVisualProvider {
                        providerPanel(
                            title: "视觉接口",
                            subtitle: "用于图片/视觉能力，可不启用",
                            provider: $controller.settings.visualProvider
                        )
                    }
                    logsPanel
                }
                .padding(22)
            }
        }
        .frame(minWidth: 760, minHeight: 680)
        .onAppear {
            controller.refreshPortOwner()
        }
        .onChange(of: controller.settings.listenAddr) { _ in
            controller.refreshPortOwner()
        }
    }

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
            Button {
                controller.saveSettings()
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)

            Button {
                controller.openSupportFolder()
            } label: {
                Label("目录", systemImage: "folder")
            }

            Button {
                controller.openConfigFile()
            } label: {
                Label("配置文件", systemImage: "doc.text")
            }

            if controller.state.isRunning {
                Button(role: .destructive) {
                    controller.stop()
                } label: {
                    Label("关闭服务", systemImage: "stop.fill")
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button {
                    controller.start()
                } label: {
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
                    TextField("4096", text: $controller.settings.maxTokens)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func providerPanel(
        title: String,
        subtitle: String,
        provider: Binding<ProviderSettings>
    ) -> some View {
        SectionPanel(title: title, subtitle: subtitle) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    FieldLabel("名称")
                    TextField("deepseek", text: provider.name)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    FieldLabel("接口地址")
                    TextField("https://api.example.com/anthropic", text: provider.baseURL)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    FieldLabel("API Key")
                    SecureField("sk-...", text: provider.apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    FieldLabel("模型名")
                    TextField("deepseek-v4-pro", text: provider.model)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    FieldLabel("协议版本")
                    TextField("2023-06-01", text: provider.version)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

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
            .frame(minHeight: 150, maxHeight: 210)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor))
            )
        }
    }
}

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

    init(_ text: String) {
        self.text = text
    }

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
        case .running, .externalRunning:
            return "checkmark.circle.fill"
        case .starting, .stopping:
            return "clock.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .stopped:
            return "circle"
        }
    }

    private var color: Color {
        switch state {
        case .running, .externalRunning:
            return .green
        case .starting, .stopping:
            return .orange
        case .failed:
            return .red
        case .stopped:
            return .secondary
        }
    }
}
