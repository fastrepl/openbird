import SwiftUI

@main
struct OpenbirdAppMain: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Openbird") {
            RootView(model: model)
                .frame(minWidth: 1120, minHeight: 760)
        }
    }
}
