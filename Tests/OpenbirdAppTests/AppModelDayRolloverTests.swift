import Foundation
import OpenbirdKit
import Testing
@testable import OpenbirdApp

struct AppModelDayRolloverTests {
    @Test func advancesSelectedDayWhenItWasFollowingToday() {
        let calendar = makeCalendar()
        let previousCurrentDay = makeDate(year: 2026, month: 3, day: 30, hour: 0, minute: 0, calendar: calendar)
        let selectedDay = makeDate(year: 2026, month: 3, day: 30, hour: 18, minute: 45, calendar: calendar)
        let now = makeDate(year: 2026, month: 3, day: 31, hour: 0, minute: 1, calendar: calendar)

        let advancedDay = AppModel.autoAdvancedSelectedDay(
            from: selectedDay,
            previousCurrentDay: previousCurrentDay,
            now: now,
            calendar: calendar
        )

        #expect(advancedDay == makeDate(year: 2026, month: 3, day: 31, hour: 0, minute: 0, calendar: calendar))
    }

    @Test func leavesHistoricalSelectionAloneAcrossMidnight() {
        let calendar = makeCalendar()
        let previousCurrentDay = makeDate(year: 2026, month: 3, day: 30, hour: 0, minute: 0, calendar: calendar)
        let selectedDay = makeDate(year: 2026, month: 3, day: 29, hour: 12, minute: 0, calendar: calendar)
        let now = makeDate(year: 2026, month: 3, day: 31, hour: 0, minute: 1, calendar: calendar)

        let advancedDay = AppModel.autoAdvancedSelectedDay(
            from: selectedDay,
            previousCurrentDay: previousCurrentDay,
            now: now,
            calendar: calendar
        )

        #expect(advancedDay == nil)
    }

    @Test func ignoresChecksBeforeTheDayActuallyChanges() {
        let calendar = makeCalendar()
        let previousCurrentDay = makeDate(year: 2026, month: 3, day: 30, hour: 0, minute: 0, calendar: calendar)
        let selectedDay = makeDate(year: 2026, month: 3, day: 30, hour: 12, minute: 0, calendar: calendar)
        let now = makeDate(year: 2026, month: 3, day: 30, hour: 23, minute: 59, calendar: calendar)

        let advancedDay = AppModel.autoAdvancedSelectedDay(
            from: selectedDay,
            previousCurrentDay: previousCurrentDay,
            now: now,
            calendar: calendar
        )

        #expect(advancedDay == nil)
    }

    @Test func advancesSelectedDayWhenTimezoneShiftMovesTodayForward() {
        let losAngeles = makeCalendar(timeZoneID: "America/Los_Angeles")
        let seoul = makeCalendar(timeZoneID: "Asia/Seoul")
        let previousCurrentDay = makeDate(year: 2026, month: 4, day: 4, hour: 0, minute: 0, calendar: losAngeles)
        let selectedDay = previousCurrentDay
        let now = makeDate(year: 2026, month: 4, day: 5, hour: 9, minute: 0, calendar: seoul)

        let advancedDay = AppModel.autoAdvancedSelectedDay(
            from: selectedDay,
            previousCurrentDay: previousCurrentDay,
            now: now,
            calendar: seoul
        )

        #expect(advancedDay == makeDate(year: 2026, month: 4, day: 5, hour: 0, minute: 0, calendar: seoul))
    }

    @Test func returnsOnlyActivityEventsMissingFromJournalCoverage() {
        let calendar = makeCalendar()
        let start = makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0, calendar: calendar)
        let compiledEvent = ActivityEvent(
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Compiled",
            url: "https://openbird.app",
            visibleText: "Already included",
            source: "accessibility",
            contentHash: "compiled",
            isExcluded: false
        )
        let uncompiledEvent = ActivityEvent(
            startedAt: start.addingTimeInterval(120),
            endedAt: start.addingTimeInterval(180),
            bundleId: "com.apple.Terminal",
            appName: "Terminal",
            windowTitle: "Build",
            url: nil,
            visibleText: "Ran swift build",
            source: "accessibility",
            contentHash: "uncompiled",
            isExcluded: false
        )
        let excludedEvent = ActivityEvent(
            startedAt: start.addingTimeInterval(240),
            endedAt: start.addingTimeInterval(300),
            bundleId: "com.apple.Messages",
            appName: "Messages",
            windowTitle: "Ignored",
            url: nil,
            visibleText: "Excluded event",
            source: "accessibility",
            contentHash: "excluded",
            isExcluded: true
        )
        let journal = DailyJournal(
            day: OpenbirdDateFormatting.dayString(for: start),
            markdown: "Summary",
            sections: [
                JournalSection(
                    heading: "Compiled work",
                    timeRange: "9:00 AM - 9:01 AM",
                    bullets: [],
                    sourceEventIDs: [compiledEvent.id]
                )
            ],
            providerID: nil
        )

        let uncompiled = AppModel.uncompiledActivityEvents(
            from: [compiledEvent, uncompiledEvent, excludedEvent],
            comparedTo: journal
        )

        #expect(uncompiled == [uncompiledEvent])
    }

    @Test func returnsNoUncompiledActivityWhenJournalAlreadyCoversVisibleEvents() {
        let calendar = makeCalendar()
        let start = makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 0, calendar: calendar)
        let firstEvent = ActivityEvent(
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Research",
            url: "https://example.com",
            visibleText: "Read the docs",
            source: "accessibility",
            contentHash: "covered-1",
            isExcluded: false
        )
        let secondEvent = ActivityEvent(
            startedAt: start.addingTimeInterval(120),
            endedAt: start.addingTimeInterval(240),
            bundleId: "com.apple.Xcode",
            appName: "Xcode",
            windowTitle: "Fix",
            url: nil,
            visibleText: "Patched the issue",
            source: "accessibility",
            contentHash: "covered-2",
            isExcluded: false
        )
        let journal = DailyJournal(
            day: OpenbirdDateFormatting.dayString(for: start),
            markdown: "Summary",
            sections: [
                JournalSection(
                    heading: "Morning",
                    timeRange: "10:00 AM - 10:04 AM",
                    bullets: [],
                    sourceEventIDs: [firstEvent.id, secondEvent.id]
                )
            ],
            providerID: nil
        )

        let uncompiled = AppModel.uncompiledActivityEvents(
            from: [firstEvent, secondEvent],
            comparedTo: journal
        )

        #expect(uncompiled.isEmpty)
    }

    private func makeCalendar(timeZoneID: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
