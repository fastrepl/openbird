import AppKit
import OpenbirdKit
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    let appLifecycle: AppLifecycleController
    @Environment(\.openWindow) private var openWindow
    private let captureStatusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var dismissedGoogleDocsHintEventID: String?

    var body: some View {
        TodayView(model: model)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                CaptureToolbarButton(model: model)
            }
            if model.availableUpdate != nil || model.isUpdateRestartPending {
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
            configureAppLifecycle()
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

    private func configureAppLifecycle() {
        appLifecycle.configure(
            openMainWindow: {
                openWindow(id: OpenbirdSceneID.main)
                NSApp.activate(ignoringOtherApps: true)
            },
            prepareForTermination: {
                await model.prepareForTermination()
            }
        )
        model.setQuitApplicationHandler {
            appLifecycle.quitCompletely()
        }
    }
}

private struct CaptureToolbarButton: View {
    @ObservedObject var model: AppModel
    @State private var isHovering = false

    private var isActivelyCapturing: Bool {
        guard model.isCapturePaused == false else { return false }
        guard model.isCollectorActiveElsewhere == false else { return false }
        guard model.isCollectorHeartbeatFresh else { return false }
        return model.settings.collectorStatus == "running"
    }

    private var statusColor: Color {
        if model.isCapturePaused { return .orange }
        if model.isCollectorActiveElsewhere { return .secondary }
        if model.isCollectorHeartbeatFresh == false { return .secondary }
        switch model.settings.collectorStatus {
        case "running":
            return .accentColor
        case "error":
            return .red
        default:
            return .secondary
        }
    }

    private var actionTitle: String {
        model.isCapturePaused ? "Resume" : "Pause"
    }

    private var buttonTitle: String {
        isHovering ? actionTitle : model.captureStatusLabel
    }

    private var hoverSymbolName: String {
        model.isCapturePaused ? "play.fill" : "pause.fill"
    }

    private var statusSymbolName: String {
        if model.isCapturePaused { return "pause.fill" }
        if model.isCollectorActiveElsewhere { return "desktopcomputer" }
        if model.isCollectorHeartbeatFresh == false { return "stop.fill" }
        switch model.settings.collectorStatus {
        case "running":
            return "record.circle.fill"
        case "error":
            return "exclamationmark"
        default:
            return "stop.fill"
        }
    }

    private var symbolName: String {
        isHovering ? hoverSymbolName : statusSymbolName
    }

    private var symbolColor: Color {
        isHovering ? .primary : statusColor
    }

    private var iconBackgroundColor: Color {
        let opacity = isHovering ? 0.18 : 0.12
        return statusColor.opacity(opacity)
    }

    private var buttonBackgroundColor: Color {
        isHovering ? statusColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor)
    }

    var body: some View {
        Button {
            model.toggleCapturePaused()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconBackgroundColor)
                    Image(systemName: symbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(symbolColor)
                        .symbolEffect(.pulse, isActive: isActivelyCapturing && isHovering == false)
                }
                .frame(width: 22, height: 22)

                ZStack(alignment: .leading) {
                    Text(model.captureStatusLabel)
                        .hidden()
                    Text(actionTitle)
                        .hidden()
                    Text(buttonTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(buttonBackgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(model.captureStatusLabel)\n\(model.captureStatusDetail)")
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct UpdateToolbarButton: View {
    @ObservedObject var model: AppModel
    @State private var isHovering = false

    private var title: String {
        if model.isUpdateRestartPending {
            return "Restart to Update"
        }
        if model.isInstallingUpdate {
            return "Updating…"
        }
        if let update = model.availableUpdate {
            return "Update to \(update.version)"
        }
        return model.isCheckingForUpdates ? "Checking…" : "Check for Updates"
    }

    private var helpText: String {
        if model.isUpdateRestartPending, let update = model.availableUpdate {
            return "Restart Openbird to finish installing \(update.version)."
        }
        if let update = model.availableUpdate {
            return "Install Openbird \(update.version)"
        }
        if model.appVersion == nil {
            return "Automatic updates are only available in packaged Openbird releases."
        }
        return "Check for a newer Openbird release."
    }

    private var tintColor: Color {
        (model.availableUpdate == nil && model.isUpdateRestartPending == false) ? .secondary : .accentColor
    }

    private var borderColor: Color {
        if model.availableUpdate != nil {
            return tintColor.opacity(isHovering ? 0.3 : 0.24)
        }
        return isHovering ? tintColor.opacity(0.22) : Color(nsColor: .separatorColor).opacity(0.35)
    }

    private var backgroundColor: Color {
        if model.availableUpdate != nil {
            return tintColor.opacity(isHovering ? 0.18 : 0.14)
        }
        return isHovering ? tintColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor)
    }

    private var symbolName: String {
        if model.isUpdateRestartPending {
            return "arrow.clockwise"
        }
        if model.availableUpdate != nil {
            return "arrow.down"
        }
        return "arrow.clockwise"
    }

    var body: some View {
        Button {
            if model.isUpdateRestartPending {
                model.restartToFinishUpdate()
            } else if model.availableUpdate != nil {
                model.installAvailableUpdate()
            } else {
                model.checkForUpdates()
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tintColor.opacity((model.availableUpdate != nil || model.isUpdateRestartPending) ? 0.18 : 0.12))
                    if model.isInstallingUpdate || model.isCheckingForUpdates {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: symbolName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tintColor)
                    }
                }
                .frame(width: 22, height: 22)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isInstallingUpdate || model.isCheckingForUpdates || (model.availableUpdate == nil && model.isUpdateRestartPending == false && model.appVersion == nil))
        .help(helpText)
        .onHover { hovering in
            isHovering = hovering
        }
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
