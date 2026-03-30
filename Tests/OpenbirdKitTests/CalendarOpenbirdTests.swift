import Foundation
import Testing
@testable import OpenbirdKit

struct CalendarOpenbirdTests {
    @Test func dayRangeIncludesEventsInFinalSecondOfDay() async throws {
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let day = try #require(calendar.date(from: DateComponents(
            timeZone: utc,
            year: 2026,
            month: 3,
            day: 30
        )))
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: day))

        try await store.saveActivityEvent(
            ActivityEvent(
                startedAt: nextDay.addingTimeInterval(-0.75),
                endedAt: nextDay.addingTimeInterval(-0.25),
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: "Late work",
                url: nil,
                visibleText: "Wrapped up work right before midnight",
                source: "accessibility",
                contentHash: "late-night",
                isExcluded: false
            )
        )

        let events = try await store.loadActivityEvents(in: calendar.dayRange(for: day))

        #expect(events.count == 1)
        #expect(events.first?.windowTitle == "Late work")
    }
}
