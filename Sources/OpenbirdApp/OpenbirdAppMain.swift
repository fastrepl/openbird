import SwiftUI

private enum OpenbirdSceneID {
    static let main = "main"
}

@main
struct OpenbirdAppMain: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Openbird", id: OpenbirdSceneID.main) {
            RootView(model: model)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }
            model.handleAppDidBecomeActive()
        }
        .commands {
            OpenbirdAppCommands(model: model)
        }

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 760, idealWidth: 760, minHeight: 640, idealHeight: 640)
        }
    }
}

private struct OpenbirdAppCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                model.checkForUpdates()
            }
        }
    }
}
