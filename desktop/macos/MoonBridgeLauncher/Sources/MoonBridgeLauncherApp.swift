import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            ServiceController.shared.terminateOnQuit()
        }
    }
}

@main
struct MoonBridgeLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("打开配置目录") {
                    Task { @MainActor in
                        ServiceController.shared.openSupportFolder()
                    }
                }
            }
        }
    }
}
