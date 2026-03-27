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
            .overlay(alignment: .bottomLeading) {
                CaptureStatusView(model: model)
                    .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(model.settings.capturePaused ? "Resume Capture" : "Pause Capture") {
                    model.toggleCapturePaused()
                }
            }
            ToolbarItem(placement: .automatic) {
                Button("Refresh") {
                    Task { await model.refresh() }
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

private struct CaptureStatusView: View {
    @ObservedObject var model: AppModel

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

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.captureStatusLabel)
                    .font(.headline)
                Text(model.captureStatusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(model.settings.capturePaused ? "Resume" : "Pause") {
                model.toggleCapturePaused()
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: 320)
    }
}
