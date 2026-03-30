import Foundation

public extension Calendar {
    func dayRange(for date: Date) -> ClosedRange<Date> {
        guard let interval = dateInterval(of: .day, for: date) else {
            let start = startOfDay(for: date)
            return start...start
        }

        let inclusiveEnd = Date(timeIntervalSinceReferenceDate: interval.end.timeIntervalSinceReferenceDate.nextDown)
        return interval.start...inclusiveEnd
    }
}
