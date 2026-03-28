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

    private var isActivelyCapturing: Bool {
        guard model.settings.capturePaused == false else { return false }
        guard model.isCollectorActiveElsewhere == false else { return false }
        guard model.isCollectorHeartbeatFresh else { return false }
        return model.settings.collectorStatus == "running"
    }

    private var statusColor: Color {
        if model.settings.capturePaused { return .orange }
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
        model.settings.capturePaused ? "Resume Capture" : "Pause Capture"
    }

    private var buttonTitle: String {
        isHovering ? actionTitle : model.captureStatusLabel
    }

    private var hoverSymbolName: String {
        model.settings.capturePaused ? "play.fill" : "pause.fill"
    }

    private var statusSymbolName: String {
        if model.settings.capturePaused { return "pause.fill" }
        if model.isCollectorActiveElsewhere { return "desktopcomputer" }
        if model.isCollectorHeartbeatFresh == false { return "stop.fill" }
        switch model.settings.collectorStatus {
        case "running":
            return "waveform"
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

    private var buttonBorderColor: Color {
        isHovering ? statusColor.opacity(0.24) : Color(nsColor: .separatorColor).opacity(0.35)
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
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(buttonBorderColor, lineWidth: 1)
            }
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

    private var tintColor: Color {
        model.availableUpdate == nil ? .secondary : .accentColor
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
        if model.availableUpdate != nil {
            return "arrow.down"
        }
        return "arrow.clockwise"
    }

    var body: some View {
        Button {
            if model.availableUpdate != nil {
                model.installAvailableUpdate()
            } else {
                model.checkForUpdates()
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tintColor.opacity(model.availableUpdate != nil ? 0.18 : 0.12))
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
        .disabled(model.isInstallingUpdate || model.isCheckingForUpdates || (model.availableUpdate == nil && model.appVersion == nil))
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
