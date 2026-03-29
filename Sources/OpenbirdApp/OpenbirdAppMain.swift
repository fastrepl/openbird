import AppKit
import SwiftUI

enum OpenbirdSceneID {
    static let main = "main"
}

@main
struct OpenbirdAppMain: App {
    @NSApplicationDelegateAdaptor(AppLifecycleController.self) private var appLifecycle
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Openbird", id: OpenbirdSceneID.main) {
            RootView(model: model, appLifecycle: appLifecycle)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }
            model.handleAppDidBecomeActive()
        }
        .commands {
            OpenbirdAppCommands(model: model, appLifecycle: appLifecycle)
        }

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 760, idealWidth: 760, minHeight: 640, idealHeight: 640)
        }

        MenuBarExtra {
            OpenbirdStatusMenu(model: model, appLifecycle: appLifecycle)
        } label: {
            OpenbirdStatusMenuLabel()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct OpenbirdAppCommands: Commands {
    @ObservedObject var model: AppModel
    let appLifecycle: AppLifecycleController
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                model.checkForUpdates()
            }
        }

        CommandGroup(replacing: .appTermination) {
            Button("Close Openbird") {
                appLifecycle.closeAllWindows()
            }
            .keyboardShortcut("q", modifiers: [.command])
        }

        CommandMenu("Chat") {
            Button("Focus Chat") {
                openWindow(id: OpenbirdSceneID.main)
                model.requestChatFocus()
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("j", modifiers: [.command])
        }
    }
}

private struct OpenbirdStatusMenu: View {
    @ObservedObject var model: AppModel
    let appLifecycle: AppLifecycleController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open App") {
            openApp()
        }

        Button("Check for Updates") {
            openApp()
            model.checkForUpdates()
        }

        Divider()

        Button("Quit Completely") {
            appLifecycle.quitCompletely()
        }
    }

    private func openApp() {
        openWindow(id: OpenbirdSceneID.main)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct OpenbirdStatusMenuLabel: View {
    private let iconSize: CGFloat = 18

    var body: some View {
        Image(nsImage: trayIcon)
            .resizable()
            .scaledToFit()
            .frame(width: iconSize, height: iconSize)
            .accessibilityLabel("Openbird")
    }

    private var trayIcon: NSImage {
        let icon = trayResourceIcon() ?? fallbackIcon()
        icon.size = NSSize(width: iconSize, height: iconSize)
        return icon
    }

    private func trayResourceIcon() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "tray", withExtension: "png"),
              let icon = NSImage(contentsOf: url) else {
            return nil
        }

        return icon
    }

    private func fallbackIcon() -> NSImage {
        NSImage(systemSymbolName: "bird", accessibilityDescription: "Openbird")
            ?? NSImage()
    }
}
