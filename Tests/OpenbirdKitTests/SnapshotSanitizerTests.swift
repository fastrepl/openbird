import Testing
@testable import OpenbirdKit

struct SnapshotSanitizerTests {
    @Test func normalizesSlackTitlesAndRemovesDuplicateVisibleText() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.tinyspeck.slackmacgap",
            appName: "Slack",
            windowTitle: "product (Channel) - Fastrepl - 1 new item - Slack",
            url: nil,
            visibleText: "product (Channel) - Fastrepl - 1 new item - Slack",
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "product (Channel)")
        #expect(sanitized.visibleText.isEmpty)
    }

    @Test func usesNormalizedSlackVisibleTextWhenWindowTitleIsGeneric() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.tinyspeck.slackmacgap",
            appName: "Slack",
            windowTitle: "Slack",
            url: nil,
            visibleText: "alert-users (Channel) - Fastrepl - 1 new item - Slack",
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "alert-users (Channel)")
        #expect(sanitized.visibleText.isEmpty)
    }

    @Test func removesGenericCodexVisibleText() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.openai.codex",
            appName: "Codex",
            windowTitle: "Codex",
            url: nil,
            visibleText: "Codex",
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "Codex")
        #expect(sanitized.visibleText.isEmpty)
    }

    @Test func fallsBackToMeaningfulVisibleTextWhenWindowTitleIsMissing() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.johnjeong.philo",
            appName: "Philo",
            windowTitle: "",
            url: nil,
            visibleText: """
            Project notes
            Start meeting recording
            Pin window
            Ship activity tracking fix
            """,
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "Project notes")
        #expect(sanitized.visibleText == "Ship activity tracking fix")
    }
}
