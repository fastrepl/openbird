import Foundation

public struct GroupedActivityEvent: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let startedAt: Date
    public let endedAt: Date
    public let bundleId: String
    public let appName: String
    public let detailTitle: String?
    public let url: String?
    public let excerpt: String
    public let isExcluded: Bool
    public let sourceEventIDs: [String]

    public init(
        id: String,
        startedAt: Date,
        endedAt: Date,
        bundleId: String,
        appName: String,
        detailTitle: String?,
        url: String?,
        excerpt: String,
        isExcluded: Bool,
        sourceEventIDs: [String]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.bundleId = bundleId
        self.appName = appName
        self.detailTitle = detailTitle
        self.url = url
        self.excerpt = excerpt
        self.isExcluded = isExcluded
        self.sourceEventIDs = sourceEventIDs
    }

    public var sourceEventCount: Int {
        sourceEventIDs.count
    }

    public var displayTitle: String {
        detailTitle ?? appName
    }
}

public enum ActivityEvidencePreprocessor {
    private static let maxMergeGap: TimeInterval = 5 * 60
    private static let snapshotSanitizer = SnapshotSanitizer()
    private static let chromePhrases = [
        "enter a message",
        "voice call",
        "video call",
        "new message",
        "all folder",
        "unread folder",
        "chatroom",
        "search",
        "menu",
        "profile",
        "friends",
        "folder",
        "chats",
    ]

    public static func groupedMeaningfulEvents(from events: [ActivityEvent]) -> [GroupedActivityEvent] {
        var preparedEvents: [PreparedEvent] = []
        preparedEvents.reserveCapacity(events.count)

        for event in events {
            if event.bundleId == "com.apple.loginwindow" || normalizedComparisonKey(for: event.appName) == "loginwindow" {
                continue
            }

            guard let preparedEvent = preparedEvent(for: event) else {
                continue
            }
            preparedEvents.append(preparedEvent)
        }

        guard let firstEvent = preparedEvents.first else {
            return []
        }

        var groups: [GroupedActivityEvent] = []
        groups.reserveCapacity(preparedEvents.count)
        var currentGroup = GroupAccumulator(preparedEvent: firstEvent)

        for preparedEvent in preparedEvents.dropFirst() {
            if currentGroup.shouldMerge(with: preparedEvent) {
                currentGroup.merge(preparedEvent)
            } else {
                groups.append(currentGroup.groupedEvent)
                currentGroup = GroupAccumulator(preparedEvent: preparedEvent)
            }
        }

        groups.append(currentGroup.groupedEvent)
        return groups
    }

    public static func isMeaningful(_ event: ActivityEvent) -> Bool {
        if event.bundleId == "com.apple.loginwindow" || normalizedComparisonKey(for: event.appName) == "loginwindow" {
            return false
        }

        return preparedEvent(for: event) != nil
    }

    public static func cleanedExcerpt(for event: ActivityEvent) -> String {
        guard let preparedEvent = preparedEvent(for: event) else {
            return ""
        }

        return preparedEvent.descriptors.excerpt ?? ""
    }

    public static func summarizedURL(from urlString: String?) -> String? {
        guard let urlString,
              urlString.isEmpty == false
        else {
            return nil
        }

        guard let components = URLComponents(string: urlString),
              let host = components.host
        else {
            return String(urlString.prefix(80))
        }

        let normalizedHost = host.replacingOccurrences(of: "www.", with: "")
        let path = components.path == "/" ? "" : components.path
        let summary = normalizedHost + path

        if summary.isEmpty {
            return normalizedHost
        }

        return summary.count > 80 ? String(summary.prefix(80)) + "…" : summary
    }

    private static func cleanedVisibleText(_ text: String, excluding values: [String]) -> String? {
        var cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(
                of: #"\b\d{1,2}:\d{2}\s?(?:AM|PM)\b"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"\b\d+\s+friends?\b"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )

        for phrase in chromePhrases {
            cleaned = cleaned.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        cleaned = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.isEmpty == false else {
            return nil
        }

        let cleanedKey = normalizedComparisonKey(for: cleaned)
        guard cleanedKey.isEmpty == false else {
            return nil
        }

        let excludedKeys = values
            .compactMap(cleanText)
            .map(normalizedComparisonKey(for:))
            .filter { $0.isEmpty == false }

        guard excludedKeys.contains(cleanedKey) == false else {
            return nil
        }

        return cleaned.count > 180 ? String(cleaned.prefix(179)) + "…" : cleaned
    }

    private static func cleanText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedComparisonKey(for value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    private static func preparedEvent(for event: ActivityEvent) -> PreparedEvent? {
        let snapshot = sanitizedSnapshot(for: event)
        let descriptors = descriptorComponents(for: snapshot)
        guard descriptors.isEmpty == false else {
            return nil
        }

        return PreparedEvent(
            event: event,
            snapshot: snapshot,
            contentHash: ActivityEventContentHash.make(
                bundleId: snapshot.bundleId,
                windowTitle: snapshot.windowTitle,
                url: snapshot.url,
                visibleText: snapshot.visibleText
            ),
            descriptors: descriptors
        )
    }

    private static func sanitizedSnapshot(for event: ActivityEvent) -> WindowSnapshot {
        let snapshot = WindowSnapshot(
            capturedAt: event.endedAt,
            bundleId: event.bundleId,
            appName: event.appName,
            windowTitle: event.windowTitle,
            url: event.url,
            visibleText: event.visibleText,
            source: event.source
        )

        guard event.bundleId == "com.tinyspeck.slackmacgap" else {
            return snapshot
        }

        return snapshotSanitizer.sanitize(snapshot)
    }

    private static func descriptorComponents(for snapshot: WindowSnapshot) -> DescriptorComponents {
        var accumulator = DescriptorAccumulator()
        accumulator.include(snapshot: snapshot)
        return accumulator.components
    }

    private struct PreparedEvent {
        let event: ActivityEvent
        let snapshot: WindowSnapshot
        let contentHash: String
        let descriptors: DescriptorComponents
    }

    private struct GroupAccumulator {
        let id: String
        let bundleId: String
        let appName: String
        let isExcluded: Bool

        var startedAt: Date
        var endedAt: Date
        var sourceEventIDs: [String]
        var sourceEventHashes: Set<String>
        var descriptors: DescriptorComponents

        init(preparedEvent: PreparedEvent) {
            let event = preparedEvent.event
            id = event.id
            bundleId = event.bundleId
            appName = preparedEvent.snapshot.appName
            isExcluded = event.isExcluded
            startedAt = event.startedAt
            endedAt = event.endedAt
            sourceEventIDs = [event.id]
            sourceEventHashes = [preparedEvent.contentHash]
            descriptors = preparedEvent.descriptors
        }

        func shouldMerge(with preparedEvent: PreparedEvent) -> Bool {
            let event = preparedEvent.event
            guard bundleId == event.bundleId, isExcluded == event.isExcluded else {
                return false
            }

            let gap = event.startedAt.timeIntervalSince(endedAt)
            guard gap <= ActivityEvidencePreprocessor.maxMergeGap else {
                return false
            }

            if sourceEventHashes.contains(preparedEvent.contentHash) {
                return true
            }

            if descriptors.detailTitles.isDisjoint(with: preparedEvent.descriptors.detailTitles) == false {
                return true
            }

            if descriptors.urls.isDisjoint(with: preparedEvent.descriptors.urls) == false {
                return true
            }

            if descriptors.excerpts.isDisjoint(with: preparedEvent.descriptors.excerpts) == false {
                return true
            }

            return false
        }

        mutating func merge(_ preparedEvent: PreparedEvent) {
            let event = preparedEvent.event
            startedAt = min(startedAt, event.startedAt)
            endedAt = max(endedAt, event.endedAt)
            sourceEventIDs.append(event.id)
            sourceEventHashes.insert(preparedEvent.contentHash)

            var mergedDescriptors = DescriptorAccumulator(components: descriptors)
            mergedDescriptors.include(preparedEvent.descriptors)
            descriptors = mergedDescriptors.components
        }

        var groupedEvent: GroupedActivityEvent {
            GroupedActivityEvent(
                id: id,
                startedAt: startedAt,
                endedAt: endedAt,
                bundleId: bundleId,
                appName: appName,
                detailTitle: descriptors.preferredDetailTitle,
                url: descriptors.preferredURL,
                excerpt: descriptors.displayExcerpt,
                isExcluded: isExcluded,
                sourceEventIDs: sourceEventIDs
            )
        }
    }

    private struct DescriptorAccumulator {
        var detailTitles: Set<String>
        var urls: Set<String>
        var excerpts: Set<String>
        var preferredDetailTitle: String?
        var preferredURL: String?
        var excerptPieces: [String]

        init(components: DescriptorComponents? = nil) {
            detailTitles = components?.detailTitles ?? []
            urls = components?.urls ?? []
            excerpts = components?.excerpts ?? []
            preferredDetailTitle = components?.preferredDetailTitle
            preferredURL = components?.preferredURL
            excerptPieces = components?.excerptPieces ?? []
        }

        mutating func include(snapshot: WindowSnapshot) {
            if let detailTitle = ActivityEvidencePreprocessor.cleanText(
                ActivityEvidencePreprocessor.normalizedComparisonKey(for: snapshot.windowTitle)
                    == ActivityEvidencePreprocessor.normalizedComparisonKey(for: snapshot.appName)
                    ? nil
                    : snapshot.windowTitle
            ) {
                let key = ActivityEvidencePreprocessor.normalizedComparisonKey(for: detailTitle)
                if key.isEmpty == false {
                    detailTitles.insert(key)
                    if preferredDetailTitle == nil || detailTitle.count > (preferredDetailTitle?.count ?? 0) {
                        preferredDetailTitle = detailTitle
                    }
                }
            }

            if let rawURL = ActivityEvidencePreprocessor.cleanText(snapshot.url),
               let urlSummary = ActivityEvidencePreprocessor.summarizedURL(from: rawURL) {
                let key = ActivityEvidencePreprocessor.normalizedComparisonKey(for: urlSummary)
                if key.isEmpty == false {
                    urls.insert(key)
                    if preferredURL == nil || urlSummary.count > (ActivityEvidencePreprocessor.summarizedURL(from: preferredURL)?.count ?? 0) {
                        preferredURL = rawURL
                    }
                }
            }

            if let excerpt = ActivityEvidencePreprocessor.cleanedVisibleText(
                snapshot.visibleText,
                excluding: [snapshot.appName, snapshot.windowTitle]
            ) {
                let key = ActivityEvidencePreprocessor.normalizedComparisonKey(for: excerpt)
                if key.isEmpty == false && excerpts.insert(key).inserted {
                    excerptPieces.append(excerpt)
                }
            }
        }

        mutating func include(_ components: DescriptorComponents) {
            detailTitles.formUnion(components.detailTitles)
            urls.formUnion(components.urls)

            preferredDetailTitle = longestText(between: preferredDetailTitle, and: components.preferredDetailTitle)
            preferredURL = preferredURLWithLongestSummary(between: preferredURL, and: components.preferredURL)

            for excerpt in components.excerptPieces {
                let key = ActivityEvidencePreprocessor.normalizedComparisonKey(for: excerpt)
                if key.isEmpty == false && excerpts.insert(key).inserted {
                    excerptPieces.append(excerpt)
                }
            }
        }

        var components: DescriptorComponents {
            let displayExcerpt = excerptPieces.prefix(2).joined(separator: " • ")
            return DescriptorComponents(
                detailTitles: detailTitles,
                urls: urls,
                excerpts: excerpts,
                preferredDetailTitle: preferredDetailTitle,
                preferredURL: preferredURL,
                excerpt: excerptPieces.first,
                displayExcerpt: displayExcerpt.count > 220 ? String(displayExcerpt.prefix(219)) + "…" : displayExcerpt,
                excerptPieces: excerptPieces
            )
        }

        private func longestText(between lhs: String?, and rhs: String?) -> String? {
            switch (lhs, rhs) {
            case let (lhs?, rhs?) where rhs.count > lhs.count:
                return rhs
            case let (lhs?, _):
                return lhs
            case let (nil, rhs?):
                return rhs
            default:
                return nil
            }
        }

        private func preferredURLWithLongestSummary(between lhs: String?, and rhs: String?) -> String? {
            let lhsLength = ActivityEvidencePreprocessor.summarizedURL(from: lhs)?.count ?? 0
            let rhsLength = ActivityEvidencePreprocessor.summarizedURL(from: rhs)?.count ?? 0
            return rhsLength > lhsLength ? rhs : lhs
        }
    }

    private struct DescriptorComponents {
        let detailTitles: Set<String>
        let urls: Set<String>
        let excerpts: Set<String>
        let preferredDetailTitle: String?
        let preferredURL: String?
        let excerpt: String?
        let displayExcerpt: String
        let excerptPieces: [String]

        var isEmpty: Bool {
            detailTitles.isEmpty && urls.isEmpty && excerpts.isEmpty
        }
    }
}
