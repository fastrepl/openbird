import Foundation
import Testing
@testable import OpenbirdKit

struct ActivityEvidencePreprocessorTests {
    @Test func groupsLegacySlackTitlesIntoOneConversation() throws {
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let events = [
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(20),
                bundleId: "com.tinyspeck.slackmacgap",
                appName: "Slack",
                windowTitle: "Slack",
                url: nil,
                visibleText: "atila, Yujong Lee (DM) - Fastrepl - Slack",
                source: "accessibility",
                contentHash: "slack-legacy-1",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(21),
                endedAt: start.addingTimeInterval(40),
                bundleId: "com.tinyspeck.slackmacgap",
                appName: "Slack",
                windowTitle: "atila, Yujong Lee (DM) - Fastrepl - Slack",
                url: nil,
                visibleText: "Reply to thread in atila, Yujong Lee",
                source: "accessibility",
                contentHash: "slack-legacy-2",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(41),
                endedAt: start.addingTimeInterval(60),
                bundleId: "com.tinyspeck.slackmacgap",
                appName: "Slack",
                windowTitle: "atila, Yujong Lee (DM)",
                url: nil,
                visibleText: "",
                source: "accessibility",
                contentHash: "slack-clean",
                isExcluded: false
            ),
        ]

        let grouped = ActivityEvidencePreprocessor.groupedMeaningfulEvents(from: events)
        let firstGroup = try #require(grouped.first)

        #expect(grouped.count == 1)
        #expect(firstGroup.detailTitle == "atila, Yujong Lee (DM)")
        #expect(firstGroup.sourceEventCount == 3)
        #expect(firstGroup.excerpt.isEmpty)
    }
}
