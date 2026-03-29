import SwiftUI

struct SetupChecklistView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var model: AppModel
    private let accessibilityStatusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Finish setup")
                    .font(.title2.weight(.semibold))
                Text("Openbird starts in Today now. Turn on capture and connect a provider here when you are ready.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    permissionRow(
                        title: "Accessibility access",
                        description: "Needed to read the active window tree and build the local activity log.",
                        isComplete: model.accessibilityTrusted
                    ) {
                        if model.accessibilityTrusted {
                            Button("Remove", role: .destructive) {
                                model.openAccessibilitySettings()
                            }
                        } else {
                            HStack(spacing: 12) {
                                Button("Request Accessibility Access") {
                                    model.requestAccessibilityPermission()
                                }
                                Button("Open Accessibility Settings") {
                                    model.openAccessibilitySettings()
                                }
                            }
                        }
                    }
                    if let help = model.accessibilityGrantHelp,
                       model.accessibilityTrusted == false {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(help)
                                .foregroundStyle(.secondary)
                            if let path = model.accessibilityGrantPath {
                                Text("App: \(path)")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            if let bundleIdentifier = model.accessibilityBundleIdentifier {
                                Text("Bundle ID: \(bundleIdentifier)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.leading, 36)
                    }
                    if model.accessibilityTrusted == false,
                       model.isCollectorActiveElsewhere,
                       let ownerPath = model.collectorOwnerPath {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Another Openbird instance currently owns capture. This window still needs its own Accessibility permission.")
                                .foregroundStyle(.secondary)
                            Text(ownerPath)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(.leading, 36)
                    }
                }
                permissionRow(
                    title: "BYOK provider",
                    description: "Needed for journal generation and chat. Local and hosted providers are built in.",
                    isComplete: model.activeProvider != nil
                ) {
                    Button("Open Provider Settings") {
                        openSettings()
                    }
                }
            }
            .padding(24)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            model.refreshAccessibilityPermissionState()
        }
        .onReceive(accessibilityStatusTimer) { _ in
            model.refreshAccessibilityPermissionState()
        }
    }

    private func permissionRow<Actions: View>(
        title: String,
        description: String,
        isComplete: Bool,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .green : .secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
                actions()
                    .padding(.top, 8)
            }
        }
    }
}
