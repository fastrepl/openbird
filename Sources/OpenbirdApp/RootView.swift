import OpenbirdKit
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    private let captureStatusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Label("Today", systemImage: "sun.max")
                    .tag(AppModel.SidebarItem.today)
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
                    .tag(AppModel.SidebarItem.chat)
                Label("Settings", systemImage: "slider.horizontal.3")
                    .tag(AppModel.SidebarItem.settings)
            }
            .navigationTitle("Openbird")
        } detail: {
            Group {
                switch model.selection {
                case .today:
                    TodayView(model: model)
                case .chat:
                    ChatView(model: model)
                case .settings:
                    SettingsView(model: model)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                CaptureToolbarButton(model: model)
            }
            if model.availableUpdate != nil || model.selection == .settings {
                ToolbarItem(placement: .automatic) {
                    UpdateToolbarButton(model: model)
                }
            }
        }
        .sheet(isPresented: $model.isShowingRawLogInspector) {
            RawLogInspectorView(model: model)
        }
        .onAppear {
            Task { await model.refreshCollectorState() }
        }
        .onReceive(captureStatusTimer) { _ in
            Task { await model.refreshCollectorState() }
        }
        .alert("Openbird", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { newValue in
                if newValue == false {
                    model.errorMessage = nil
                }
            }
        )) {
            Button("OK") {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }
}

private struct CaptureToolbarButton: View {
    @ObservedObject var model: AppModel
    @State private var isHovering = false

    private var statusColor: Color {
        if model.settings.capturePaused { return .orange }
        if model.isCollectorActiveElsewhere { return .secondary }
        if model.isCollectorHeartbeatFresh == false { return .secondary }
        switch model.settings.collectorStatus {
        case "running":
            return .green
        case "error":
            return .red
        default:
            return .secondary
        }
    }

    private var buttonTitle: String {
        if isHovering {
            return model.settings.capturePaused ? "Resume Capture" : "Pause Capture"
        }
        return model.captureStatusLabel
    }

    var body: some View {
        Button {
            model.toggleCapturePaused()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(buttonTitle)
            }
        }
        .help("\(model.captureStatusLabel)\n\(model.captureStatusDetail)")
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct UpdateToolbarButton: View {
    @ObservedObject var model: AppModel

    private var title: String {
        if model.isInstallingUpdate {
            return "Updating…"
        }
        if let update = model.availableUpdate {
            return "Update to \(update.version)"
        }
        return model.isCheckingForUpdates ? "Checking…" : "Check for Updates"
    }

    private var helpText: String {
        if let update = model.availableUpdate {
            return "Install Openbird \(update.version)"
        }
        if model.appVersion == nil {
            return "Automatic updates are only available in packaged Openbird releases."
        }
        return "Check for a newer Openbird release."
    }

    var body: some View {
        Button(title) {
            if model.availableUpdate != nil {
                model.installAvailableUpdate()
            } else {
                model.checkForUpdates()
            }
        }
        .disabled(model.isInstallingUpdate || model.isCheckingForUpdates || (model.availableUpdate == nil && model.appVersion == nil))
        .help(helpText)
    }
}
