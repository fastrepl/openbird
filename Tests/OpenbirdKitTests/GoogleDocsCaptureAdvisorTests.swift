import Foundation
import Testing
@testable import OpenbirdKit

struct GoogleDocsCaptureAdvisorTests {
    @Test func skipsHintForSingleWeakGoogleDocsCapture() {
        let now = Date()

        let hint = GoogleDocsCaptureAdvisor.hint(
            for: [
                makeEvent(
                    endedAt: now.addingTimeInterval(-10),
                    url: "https://docs.google.com/document/d/abc123/edit",
                    visibleText: ""
                )
            ],
            now: now
        )

        #expect(hint == nil)
    }

    @Test func returnsHintForSustainedWeakGoogleDocsCapture() {
        let now = Date()

        let hint = GoogleDocsCaptureAdvisor.hint(
            for: [
                makeEvent(
                    startedAt: now.addingTimeInterval(-24),
                    endedAt: now.addingTimeInterval(-18),
                    url: "https://docs.google.com/document/d/abc123/edit",
                    visibleText: ""
                ),
                makeEvent(
                    startedAt: now.addingTimeInterval(-18),
                    endedAt: now.addingTimeInterval(-12),
                    url: "https://docs.google.com/document/d/abc123/edit",
                    visibleText: "Show all comments\nShare\nTools"
                ),
                makeEvent(
                    startedAt: now.addingTimeInterval(-12),
                    endedAt: now.addingTimeInterval(-6),
                    url: "https://docs.google.com/document/d/abc123/edit",
                    visibleText: "Show all comments\nShare\nTools"
                )
            ],
            now: now
        )

        #expect(hint != nil)
        #expect(hint?.shortcut == "Command + Option + Z")
    }

    @Test func skipsHintWhenGoogleDocsCaptureContainsDocumentText() {
        let now = Date()

        let hint = GoogleDocsCaptureAdvisor.hint(
            for: [
                makeEvent(
                    endedAt: now.addingTimeInterval(-10),
                    url: "https://docs.google.com/document/d/abc123/edit",
                    visibleText: "Launch checklist\nFinalize the release notes for the signed DMG build and send the updated draft to the team."
                )
            ],
            now: now
        )

        #expect(hint == nil)
    }

    @Test func skipsHintWhenRecentWeakCaptureFollowsStrongCapture() {
        let now = Date()

        let hint = GoogleDocsCaptureAdvisor.hint(
            for: [
                makeEvent(
                    startedAt: now.addingTimeInterval(-26),
                    endedAt: now.addingTimeInterval(-20),
                    url: "https://docs.google.com/document/d/abc123/edit",
                    visibleText: "Launch checklist\nFinalize the release notes for the signed DMG build."
                ),
                makeEvent(
                    startedAt: now.addingTimeInterval(-12),
                    endedAt: now.addingTimeInterval(-6),
                    url: "https://docs.google.com/document/d/abc123/edit",
                    visibleText: "Show all comments\nShare\nTools"
                ),
                makeEvent(
                    startedAt: now.addingTimeInterval(-6),
                    endedAt: now.addingTimeInterval(-1),
                    url: "https://docs.google.com/document/d/abc123/edit",
                    visibleText: ""
                )
            ],
            now: now
        )

        #expect(hint == nil)
    }

    @Test func skipsHintForStaleOrNonDocsEvents() {
        let now = Date()

        let staleHint = GoogleDocsCaptureAdvisor.hint(
            for: [
                makeEvent(
                    endedAt: now.addingTimeInterval(-180),
                    url: "https://docs.google.com/document/d/abc123/edit",
                    visibleText: ""
                )
            ],
            now: now
        )

        let nonDocsHint = GoogleDocsCaptureAdvisor.hint(
            for: [
                makeEvent(
                    endedAt: now.addingTimeInterval(-10),
                    url: "https://mail.google.com/mail/u/0/#inbox",
                    visibleText: ""
                )
            ],
            now: now
        )

        #expect(staleHint == nil)
        #expect(nonDocsHint == nil)
    }

    private func makeEvent(
        startedAt: Date? = nil,
        endedAt: Date,
        url: String,
        visibleText: String
    ) -> ActivityEvent {
        ActivityEvent(
            id: UUID().uuidString,
            startedAt: startedAt ?? endedAt.addingTimeInterval(-6),
            endedAt: endedAt,
            bundleId: "com.google.Chrome",
            appName: "Google Chrome",
            windowTitle: "Doc title - Google Docs",
            url: url,
            visibleText: visibleText,
            source: "accessibility",
            contentHash: UUID().uuidString,
            isExcluded: false
        )
    }
}
