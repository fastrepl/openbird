import AppKit
import OpenbirdKit
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    private let captureStatusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var dismissedGoogleDocsHintEventID: String?

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
        .overlay(alignment: .top) {
            if let hint = visibleGoogleDocsCaptureHint {
                GoogleDocsCaptureNotification(
                    hint: hint,
                    dismiss: {
                        dismissedGoogleDocsHintEventID = hint.eventID
                    }
                )
                .padding(.top, 18)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
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
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: visibleGoogleDocsCaptureHint?.eventID)
    }

    private var visibleGoogleDocsCaptureHint: GoogleDocsCaptureHint? {
        guard let hint = model.googleDocsCaptureHint else {
            return nil
        }
        guard dismissedGoogleDocsHintEventID != hint.eventID else {
            return nil
        }
        return hint
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

    private var actionTitle: String {
        model.settings.capturePaused ? "Resume Capture" : "Pause Capture"
    }

    private var buttonTitle: String {
        isHovering ? actionTitle : model.captureStatusLabel
    }

    private var hoverSymbolName: String {
        model.settings.capturePaused ? "play.fill" : "pause.fill"
    }

    var body: some View {
        Button {
            model.toggleCapturePaused()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .opacity(isHovering ? 0 : 1)
                    Image(systemName: hoverSymbolName)
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(isHovering ? 1 : 0)
                }
                .frame(width: 10, height: 10)

                ZStack(alignment: .leading) {
                    Text(model.captureStatusLabel)
                        .hidden()
                    Text(actionTitle)
                        .hidden()
                    Text(buttonTitle)
                }
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

private struct GoogleDocsCaptureNotification: View {
    let hint: GoogleDocsCaptureHint
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("Openbird needs a Google Docs setting")
                    .font(.headline)
                Text("Turn on screen reader support so Openbird can read this Google Doc.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Text(hint.shortcut)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Link("Show me how", destination: hint.helpURL)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(width: 440, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
    }
}
