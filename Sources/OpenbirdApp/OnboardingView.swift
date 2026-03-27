import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Openbird")
                .font(.system(size: 40, weight: .semibold))

            Text("A local-first activity journal for macOS.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                permissionRow(
                    title: "Accessibility access",
                    description: "Needed to read the active window tree and build the local activity log.",
                    isComplete: model.accessibilityTrusted
                )
                permissionRow(
                    title: "BYOK provider",
                    description: "Needed for journal generation and chat. Local and hosted providers are built in.",
                    isComplete: model.activeProvider != nil
                )
            }
            .padding(24)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Never captured by default")
                    .font(.headline)
                Text("Raw key events, clipboard contents, hidden windows, secure text fields, passwords, and automatic screenshots.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Request Accessibility Access") {
                    model.requestAccessibilityPermission()
                }
                Button("Open Accessibility Settings") {
                    model.openAccessibilitySettings()
                }
                Button("Open Provider Settings") {
                    model.selection = .settings
                }
            }

            if model.needsOnboarding == false {
                Button("Continue to Today") {
                    model.selection = .today
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding(40)
    }

    private func permissionRow(title: String, description: String, isComplete: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .green : .secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
