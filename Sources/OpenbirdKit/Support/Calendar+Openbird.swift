import Foundation

public extension Calendar {
    func dayRange(for date: Date) -> ClosedRange<Date> {
        let start = startOfDay(for: date)
        let end = self.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? start
        return start...end
    }
}
