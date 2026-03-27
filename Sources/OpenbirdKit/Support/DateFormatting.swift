import Foundation

public enum OpenbirdDateFormatting {
    public static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    public static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    public static func dayString(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    public static func timeString(for date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
