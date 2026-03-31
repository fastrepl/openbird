import Foundation

public struct GoogleDocsCaptureHint: Equatable, Sendable {
    public let eventID: String
    public let helpURL: URL
    public let shortcut: String

    public init(
        eventID: String,
        helpURL: URL = URL(string: "https://support.google.com/docs/answer/6282736?hl=en")!,
        shortcut: String = "Command + Option + Z"
    ) {
        self.eventID = eventID
        self.helpURL = helpURL
        self.shortcut = shortcut
    }
}

public enum GoogleDocsCaptureAdvisor {
    private static let recentEventWindow: TimeInterval = 90
    private static let minimumWeakCaptureStreak: TimeInterval = 18
    private static let maximumWeakCaptureGap: TimeInterval = 8

    public static func hint(for events: [ActivityEvent], now: Date = Date()) -> GoogleDocsCaptureHint? {
        let recentEvents = recentGoogleDocsEvents(in: events, now: now)

        guard let event = mostRecentGoogleDocsEvent(in: recentEvents),
              hasWeakCapture(event),
              weakCaptureStreakEnding(with: event, in: recentEvents) >= minimumWeakCaptureStreak
        else {
            return nil
        }

        return GoogleDocsCaptureHint(eventID: event.id)
    }

    private static func recentGoogleDocsEvents(in events: [ActivityEvent], now: Date) -> [ActivityEvent] {
        events.filter { event in
            isGoogleDocsDocumentEvent(event) && now.timeIntervalSince(event.endedAt) <= recentEventWindow
        }
    }

    private static func mostRecentGoogleDocsEvent(in events: [ActivityEvent]) -> ActivityEvent? {
        events
            .max { lhs, rhs in
                if lhs.endedAt != rhs.endedAt {
                    return lhs.endedAt < rhs.endedAt
                }
                return lhs.startedAt < rhs.startedAt
            }
    }

    private static func weakCaptureStreakEnding(
        with latestEvent: ActivityEvent,
        in events: [ActivityEvent]
    ) -> TimeInterval {
        let sortedEvents = events.sorted { lhs, rhs in
            if lhs.endedAt != rhs.endedAt {
                return lhs.endedAt < rhs.endedAt
            }
            return lhs.startedAt < rhs.startedAt
        }

        guard let latestIndex = sortedEvents.lastIndex(where: { $0.id == latestEvent.id }) else {
            return latestEvent.endedAt.timeIntervalSince(latestEvent.startedAt)
        }

        var streakStart = latestEvent.startedAt
        var previousStart = latestEvent.startedAt

        for event in sortedEvents[..<latestIndex].reversed() {
            let gap = previousStart.timeIntervalSince(event.endedAt)
            guard gap <= maximumWeakCaptureGap, hasWeakCapture(event) else {
                break
            }

            streakStart = min(streakStart, event.startedAt)
            previousStart = event.startedAt
        }

        return latestEvent.endedAt.timeIntervalSince(streakStart)
    }

    private static func isGoogleDocsDocumentEvent(_ event: ActivityEvent) -> Bool {
        guard let url = event.url,
              let components = URLComponents(string: url),
              let host = components.host?.lowercased()
        else {
            return false
        }

        return host == "docs.google.com" && components.path.hasPrefix("/document/")
    }

    private static func hasWeakCapture(_ event: ActivityEvent) -> Bool {
        let lines = event.visibleText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        if lines.isEmpty {
            return true
        }

        let normalizedLines = lines.map(\.normalizedComparisonKey)
        let combinedLength = lines.joined(separator: " ").count

        if combinedLength >= 120 {
            return false
        }

        if normalizedLines.allSatisfy({ docsChromeLines.contains($0) }) {
            return true
        }

        let shortChromeLikeLineCount = normalizedLines.filter { line in
            line.isEmpty == false && line.count <= 24 && line.split(separator: " ").count <= 4
        }.count

        return combinedLength <= 80 && shortChromeLikeLineCount == normalizedLines.count
    }
}

private extension String {
    var normalizedComparisonKey: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}

private let docsChromeLines: Set<String> = [
    "comment",
    "comment history",
    "comments",
    "editing",
    "extensions",
    "file",
    "format",
    "help",
    "insert",
    "last edit was seconds ago",
    "menus",
    "share",
    "show all comments",
    "suggesting",
    "tools",
    "view",
]
