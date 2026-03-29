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
        Button("Open Openbird") {
            openApp()
        }

        Button("Settings") {
            openSettings()
        }

        Menu("Pause Context Collection") {
            if model.isCapturePaused {
                Button("Resume now") {
                    model.resumeCapture()
                }

                Divider()
            }

            Button("For 5 minutes") {
                model.pauseCapture(for: 5 * 60)
            }

            Button("For 15 minutes") {
                model.pauseCapture(for: 15 * 60)
            }

            Button("For 30 minutes") {
                model.pauseCapture(for: 30 * 60)
            }

            Button("For an hour") {
                model.pauseCapture(for: 60 * 60)
            }

            Divider()

            Button("Until next launch") {
                model.pauseCaptureUntilNextLaunch()
            }
        }

        Menu("Exclude") {
            Button(model.currentAppExclusionTitle) {
                model.excludeCurrentApp()
            }
            .disabled(model.canExcludeCurrentApp == false)

            Divider()

            Button(model.currentDomainExclusionTitle) {
                model.excludeCurrentDomain()
            }
            .disabled(model.canExcludeCurrentDomain == false)
        }

        if let versionText = model.menuVersionText {
            Divider()

            Button(versionText) {}
                .disabled(true)
        }

        if let updateStatusText = model.menuUpdateStatusText {
            Button(updateStatusText) {}
                .disabled(true)
        }

        Button("Check for Updates") {
            model.checkForUpdates()
        }

        Divider()

        Button("Quit Openbird Completely") {
            appLifecycle.quitCompletely()
        }
        .onAppear {
            model.refreshStatusMenuContext()
            Task { await model.refreshCollectorState() }
        }
    }

    private func openApp() {
        openWindow(id: OpenbirdSceneID.main)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

private struct OpenbirdStatusMenuLabel: View {
    private let iconSize: CGFloat = 18
    private static let trayImageSearchURLs: [URL] = {
        let fileManager = FileManager.default
        let searchDirectories = [
            Bundle.main.resourceURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ].compactMap { $0 }
        var urls: [URL] = []
        var seenPaths = Set<String>()

        for directory in searchDirectories {
            let directImageURL = directory.appendingPathComponent("tray.png")
            if seenPaths.insert(directImageURL.path).inserted {
                urls.append(directImageURL)
            }

            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for bundleURL in contents where bundleURL.pathExtension == "bundle" {
                let imageURL = bundleURL.appendingPathComponent("tray.png")
                if seenPaths.insert(imageURL.path).inserted {
                    urls.append(imageURL)
                }
            }
        }

        return urls
    }()

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
        for url in Self.trayImageSearchURLs {
            if let icon = NSImage(contentsOf: url) {
                return icon
            }
        }

        return nil
    }

    private func fallbackIcon() -> NSImage {
        NSImage(systemSymbolName: "bird", accessibilityDescription: "Openbird")
            ?? NSImage()
    }
}
