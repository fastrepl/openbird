import Foundation
import Testing
@testable import OpenbirdApp

struct TimelineInsightBuilderTests {
    @Test func mergesAdjacentCommunicationActivityIntoOneInsight() {
        let base = Self.makeDate(hour: 8, minute: 44)
        let items = [
            Self.makeItem(
                startedAt: base,
                endedAt: base.addingTimeInterval(60),
                appName: "KakaoTalk",
                title: "황보민경",
                bullets: ["Asked whether the medicine was helping"]
            ),
            Self.makeItem(
                startedAt: base.addingTimeInterval(2 * 60),
                endedAt: base.addingTimeInterval(3 * 60),
                appName: "WhatsApp",
                title: "Demo thread",
                bullets: ["Replied with the latest build"]
            ),
        ]

        let insights = TimelineInsightBuilder.build(from: items)

        #expect(insights.count == 1)
        #expect(insights[0].kind == .communication)
        #expect(insights[0].apps == ["KakaoTalk", "WhatsApp"])
        #expect(insights[0].title == "Messages about Demo thread")
    }

    @Test func keepsDifferentWorkModesSeparated() {
        let base = Self.makeDate(hour: 9, minute: 0)
        let items = [
            Self.makeItem(
                startedAt: base,
                endedAt: base.addingTimeInterval(2 * 60),
                appName: "Safari",
                title: "OpenAI pricing",
                bullets: ["openai.com/pricing"]
            ),
            Self.makeItem(
                startedAt: base.addingTimeInterval(5 * 60),
                endedAt: base.addingTimeInterval(12 * 60),
                appName: "Xcode",
                title: "TodayView.swift",
                bullets: ["Adjusted the timeline grouping logic"]
            ),
        ]

        let insights = TimelineInsightBuilder.build(from: items)

        #expect(insights.count == 2)
        #expect(insights[0].kind == .research)
        #expect(insights[1].kind == .development)
    }

    @Test func foldsRepeatedUpdatePromptsIntoSingleMaintenanceInsight() {
        let base = Self.makeDate(hour: 10, minute: 12)
        let items = [
            Self.makeItem(
                startedAt: base,
                endedAt: base.addingTimeInterval(30),
                appName: "WhatsApp",
                title: "Update WhatsApp",
                bullets: ["This version of WhatsApp will expire in 13 days"]
            ),
            Self.makeItem(
                startedAt: base.addingTimeInterval(90),
                endedAt: base.addingTimeInterval(120),
                appName: "WhatsApp",
                title: "Update WhatsApp",
                bullets: ["This version of WhatsApp will expire in 13 days"]
            ),
        ]

        let insights = TimelineInsightBuilder.build(from: items)

        #expect(insights.count == 1)
        #expect(insights[0].kind == .admin)
        #expect(insights[0].title == "WhatsApp upkeep")
        #expect(insights[0].itemCount == 2)
    }

    private static func makeItem(
        startedAt: Date,
        endedAt: Date,
        appName: String,
        title: String,
        bullets: [String]
    ) -> TimelineItem {
        TimelineItem(
            id: UUID().uuidString,
            startedAt: startedAt,
            endedAt: endedAt,
            title: title,
            bullets: bullets,
            sourceEventIDs: [],
            bundleId: nil,
            bundlePath: nil,
            appName: appName
        )
    }

    private static func makeDate(hour: Int, minute: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0),
                year: 2026,
                month: 3,
                day: 31,
                hour: hour,
                minute: minute
            )
        )!
    }
}
