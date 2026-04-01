import Foundation
import OpenbirdKit

struct TimelineItem: Identifiable, Sendable {
    let id: String
    let startedAt: Date
    let endedAt: Date
    let title: String
    let bullets: [String]
    let sourceEventIDs: [String]
    let bundleId: String?
    let bundlePath: String?
    let appName: String

    var timeRange: String {
        let start = OpenbirdDateFormatting.timeString(for: startedAt)
        let end = OpenbirdDateFormatting.timeString(for: endedAt)
        return start == end ? start : "\(start) - \(end)"
    }
}

struct TimelineInsightGroup: Identifiable, Sendable {
    let id: String
    let startedAt: Date
    let endedAt: Date
    let title: String
    let summary: String
    let highlights: [String]
    let apps: [String]
    let kind: TimelineInsightKind
    let itemCount: Int

    var timeRange: String {
        let start = OpenbirdDateFormatting.timeString(for: startedAt)
        let end = OpenbirdDateFormatting.timeString(for: endedAt)
        return start == end ? start : "\(start) - \(end)"
    }

    var metadata: String {
        [timeRange, durationDescription].joined(separator: " • ")
    }

    private var durationDescription: String {
        let minutes = max(1, Int(ceil(endedAt.timeIntervalSince(startedAt) / 60)))
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return hours == 1 ? "1 hr" : "\(hours) hr"
        }

        return hours == 1 ? "1 hr \(remainingMinutes) min" : "\(hours) hr \(remainingMinutes) min"
    }
}

enum TimelineInsightKind: String, Sendable {
    case communication
    case development
    case planning
    case research
    case admin
    case media
    case generic

    var symbolName: String {
        switch self {
        case .communication:
            return "bubble.left.and.bubble.right.fill"
        case .development:
            return "hammer.fill"
        case .planning:
            return "square.and.pencil"
        case .research:
            return "magnifyingglass"
        case .admin:
            return "wrench.and.screwdriver.fill"
        case .media:
            return "play.rectangle.fill"
        case .generic:
            return "sparkles"
        }
    }
}

enum TimelineInsightBuilder {
    private static let looseMergeGap: TimeInterval = 10 * 60
    private static let strongMergeGap: TimeInterval = 25 * 60
    private static let maxLooseClusterSpan: TimeInterval = 45 * 60

    static func build(from items: [TimelineItem]) -> [TimelineInsightGroup] {
        let classifiedItems = items.map(ClassifiedTimelineItem.init)
        guard let firstItem = classifiedItems.first else {
            return []
        }

        var groups: [[ClassifiedTimelineItem]] = [[firstItem]]
        groups.reserveCapacity(classifiedItems.count)

        for item in classifiedItems.dropFirst() {
            if shouldMerge(item, into: groups[groups.count - 1]) {
                groups[groups.count - 1].append(item)
            } else {
                groups.append([item])
            }
        }

        return groups.map(makeInsightGroup)
    }

    private static func shouldMerge(
        _ candidate: ClassifiedTimelineItem,
        into group: [ClassifiedTimelineItem]
    ) -> Bool {
        guard let previous = group.last else {
            return false
        }

        let gap = candidate.item.startedAt.timeIntervalSince(previous.item.endedAt)
        guard gap <= strongMergeGap else {
            return false
        }

        let appKeys = Set(group.map(\.appKey))
        if appKeys.contains(candidate.appKey) {
            return true
        }

        let signalKeys = group.reduce(into: Set<String>()) { partialResult, item in
            partialResult.formUnion(item.signalKeys)
        }
        if signalKeys.isDisjoint(with: candidate.signalKeys) == false {
            return true
        }

        let kinds = Set(group.map(\.kind))
        let clusterSpan = candidate.item.endedAt.timeIntervalSince(group[0].item.startedAt)
        return gap <= looseMergeGap && clusterSpan <= maxLooseClusterSpan && kinds.contains(candidate.kind)
    }

    private static func makeInsightGroup(from group: [ClassifiedTimelineItem]) -> TimelineInsightGroup {
        let apps = group.map(\.item.appName).deduplicatedByNormalizedText()
        let kind = dominantKind(in: group)
        let highlights = insightHighlights(from: group)
        let context = bestContext(from: group, excluding: apps)

        return TimelineInsightGroup(
            id: group[0].item.id,
            startedAt: group[0].item.startedAt,
            endedAt: group[group.count - 1].item.endedAt,
            title: insightTitle(kind: kind, context: context, apps: apps),
            summary: insightSummary(
                kind: kind,
                context: context,
                apps: apps,
                itemCount: group.count
            ),
            highlights: Array(highlights.prefix(3)),
            apps: apps,
            kind: kind,
            itemCount: group.count
        )
    }

    private static func dominantKind(in group: [ClassifiedTimelineItem]) -> TimelineInsightKind {
        group.reduce(into: [TimelineInsightKind: Int]()) { counts, item in
            counts[item.kind, default: 0] += 1
        }
        .max { lhs, rhs in
            lhs.value < rhs.value
        }?
        .key ?? .generic
    }

    private static func insightTitle(
        kind: TimelineInsightKind,
        context: String?,
        apps: [String]
    ) -> String {
        switch kind {
        case .communication:
            if let context {
                return "Messages about \(context)"
            }
            return "Messages and notifications"
        case .development:
            if let context {
                return "Working on \(context)"
            }
            return "Development session"
        case .planning:
            if let context {
                return "Planning \(context)"
            }
            return "Planning and writing"
        case .research:
            if let context {
                return "Reviewing \(context)"
            }
            return "Research and reading"
        case .admin:
            if let app = apps.first, apps.count == 1 {
                return "\(app) upkeep"
            }
            return "Maintenance and setup"
        case .media:
            if let context {
                return "Watching \(context)"
            }
            return "Media and video"
        case .generic:
            if let context {
                return "Working through \(context)"
            }
            if let app = apps.first, apps.count == 1 {
                return "\(app) activity"
            }
            return "Mixed activity block"
        }
    }

    private static func insightSummary(
        kind: TimelineInsightKind,
        context: String?,
        apps: [String],
        itemCount: Int
    ) -> String {
        let appSummary = shortList(apps, empty: "captured activity")
        let momentSummary = itemCount == 1 ? "1 captured moment" : "\(itemCount) captured moments"

        switch kind {
        case .communication:
            if let context {
                return "Communication burst around \(context) across \(appSummary), combining \(momentSummary)."
            }
            return "Communication burst across \(appSummary), combining \(momentSummary)."
        case .development:
            return "Focused development work across \(appSummary), combining \(momentSummary)."
        case .planning:
            return "Planning and writing block across \(appSummary), combining \(momentSummary)."
        case .research:
            return "Research block across \(appSummary), combining \(momentSummary)."
        case .admin:
            return "Maintenance and setup work across \(appSummary), combining \(momentSummary)."
        case .media:
            return "Media block across \(appSummary), combining \(momentSummary)."
        case .generic:
            return "Activity cluster across \(appSummary), combining \(momentSummary)."
        }
    }

    private static func bestContext(
        from group: [ClassifiedTimelineItem],
        excluding labels: [String]
    ) -> String? {
        let excludedKeys = Set(labels.map(\.normalizedComparisonKey))
        var bestMatch: (value: String, score: Int)?

        for item in group {
            for candidate in item.contextCandidates {
                let normalized = candidate.normalizedComparisonKey
                guard normalized.isEmpty == false else {
                    continue
                }
                guard excludedKeys.contains(normalized) == false else {
                    continue
                }

                let score = contextScore(
                    candidate,
                    preferredTitle: item.item.title,
                    appName: item.item.appName
                )
                guard score > 0 else {
                    continue
                }

                if let bestMatch, bestMatch.score >= score {
                    continue
                }
                bestMatch = (candidate, score)
            }
        }

        return bestMatch?.value
    }

    private static func contextScore(
        _ candidate: String,
        preferredTitle: String,
        appName: String
    ) -> Int {
        let normalized = candidate.normalizedComparisonKey
        guard normalized.isEmpty == false else {
            return 0
        }

        if looksLikeNoise(candidate) {
            return 0
        }

        var score = 1
        if normalized == preferredTitle.normalizedComparisonKey {
            score += 4
        }
        if candidate.contains(".") || candidate.contains("/") {
            score += 3
        }

        let wordCount = candidate.split(whereSeparator: \.isWhitespace).count
        if wordCount >= 2 && wordCount <= 8 {
            score += 2
        }
        if candidate.count >= 8 && candidate.count <= 80 {
            score += 1
        }
        if normalized == appName.normalizedComparisonKey {
            score = 0
        }

        return score
    }

    private static func insightHighlights(from group: [ClassifiedTimelineItem]) -> [String] {
        var highlights: [String] = []

        for item in group {
            let excludedLabels = [item.item.appName]
            if let titleHighlight = cleanedHighlight(
                item.item.title,
                excluding: excludedLabels
            ) {
                highlights.append(titleHighlight)
            }

            for bullet in item.item.bullets {
                for segment in bullet.split(separator: "•") {
                    if let highlight = cleanedHighlight(
                        String(segment).trimmingCharacters(in: .whitespacesAndNewlines),
                        excluding: excludedLabels
                    ) {
                        highlights.append(highlight)
                    }
                }
            }
        }

        return highlights.deduplicatedByNormalizedText()
    }

    private static func cleanedHighlight(
        _ value: String,
        excluding labels: [String]
    ) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.isEmpty == false else {
            return nil
        }
        guard looksLikeNoise(candidate) == false else {
            return nil
        }

        let normalized = candidate.normalizedComparisonKey
        guard normalized.isEmpty == false else {
            return nil
        }
        guard normalized.hasSuffix("grouped logs") == false else {
            return nil
        }

        let excludedKeys = Set(labels.map(\.normalizedComparisonKey))
        guard excludedKeys.contains(normalized) == false else {
            return nil
        }

        return candidate
    }

    private static func shortList(_ values: [String], empty: String) -> String {
        switch values.count {
        case 0:
            return empty
        case 1:
            return values[0]
        case 2:
            return "\(values[0]) and \(values[1])"
        default:
            return "\(values[0]), \(values[1]), and \(values.count - 2) more"
        }
    }

    private static func looksLikeNoise(_ value: String) -> Bool {
        let normalized = value.normalizedComparisonKey
        guard normalized.isEmpty == false else {
            return true
        }

        if normalized.count < 3 {
            return true
        }

        if interfaceNoiseFragments.contains(where: normalized.contains) {
            return true
        }

        return false
    }

    private static let browserAppLabels: Set<String> = [
        "safari", "google chrome", "chrome", "arc", "firefox", "brave", "microsoft edge", "edge"
    ]
    private static let communicationAppLabels: Set<String> = [
        "slack", "messages", "imessage", "discord", "kakaotalk", "telegram", "whatsapp", "mail", "gmail", "outlook", "zoom"
    ]
    private static let developmentAppLabels: Set<String> = [
        "xcode", "visual studio code", "vs code", "cursor", "zed", "terminal", "iterm2", "warp", "nova", "github desktop"
    ]
    private static let planningAppLabels: Set<String> = [
        "notion", "notes", "bear", "pages", "google docs", "obsidian", "calendar", "reminders"
    ]
    private static let mediaAppLabels: Set<String> = [
        "youtube", "spotify", "music", "podcasts", "tv"
    ]
    private static let adminCueFragments = [
        "update",
        "updates",
        "installer",
        "settings",
        "notification",
        "notifications",
        "permission",
        "permissions",
        "security",
        "expired",
        "expire",
        "version",
        "learn more"
    ]
    private static let communicationCueFragments = [
        "message",
        "messages",
        "reply",
        "replied",
        "chat",
        "call",
        "thread",
        "inbox"
    ]
    private static let developmentCueFragments = [
        "commit",
        "pull request",
        "branch",
        "repo",
        "repository",
        "build",
        "test",
        "error",
        "issue",
        "swift",
        "xcode",
        "terminal"
    ]
    private static let planningCueFragments = [
        "doc",
        "draft",
        "plan",
        "spec",
        "outline",
        "notes",
        "agenda"
    ]
    private static let mediaCueFragments = [
        "youtube",
        "video",
        "playlist",
        "music",
        "podcast"
    ]
    private static let interfaceNoiseFragments = [
        "common icon",
        "button",
        "grouped logs",
        "learn more",
        "newdot",
        "triangledown",
        "notifications settings",
        "your update will be free of charge"
    ]

    private struct ClassifiedTimelineItem {
        let item: TimelineItem
        let kind: TimelineInsightKind
        let appKey: String
        let signalKeys: Set<String>
        let contextCandidates: [String]

        init(item: TimelineItem) {
            self.item = item
            kind = Self.classify(item)
            appKey = item.appName.normalizedComparisonKey
            let candidateValues = Self.candidateValues(for: item)
            signalKeys = Set(
                candidateValues
                    .map(\.normalizedComparisonKey)
                    .filter { $0.isEmpty == false }
            )
            contextCandidates = candidateValues
        }

        private static func classify(_ item: TimelineItem) -> TimelineInsightKind {
            let appKey = item.appName.normalizedComparisonKey
            let normalizedText = ([item.title] + item.bullets)
                .joined(separator: " ")
                .normalizedComparisonKey

            if containsAny(adminCueFragments, in: normalizedText) {
                return .admin
            }
            if communicationAppLabels.contains(appKey) {
                return .communication
            }
            if developmentAppLabels.contains(appKey) {
                return .development
            }
            if planningAppLabels.contains(appKey) {
                return .planning
            }
            if mediaAppLabels.contains(appKey) {
                return .media
            }
            if containsAny(developmentCueFragments, in: normalizedText) {
                return .development
            }
            if containsAny(planningCueFragments, in: normalizedText) {
                return .planning
            }
            if containsAny(communicationCueFragments, in: normalizedText) {
                return .communication
            }
            if containsAny(mediaCueFragments, in: normalizedText) {
                return .media
            }
            if browserAppLabels.contains(appKey) || item.bullets.contains(where: { $0.contains(".") || $0.contains("/") }) {
                return .research
            }
            return .generic
        }

        private static func candidateValues(for item: TimelineItem) -> [String] {
            var values: [String] = []

            let trimmedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTitle.isEmpty == false {
                values.append(trimmedTitle)
            }

            for bullet in item.bullets {
                for segment in bullet.split(separator: "•") {
                    let candidate = String(segment).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard candidate.isEmpty == false else {
                        continue
                    }
                    values.append(candidate)
                }
            }

            return values.deduplicatedByNormalizedText()
        }

        private static func containsAny(_ fragments: [String], in value: String) -> Bool {
            fragments.contains { value.contains($0.normalizedComparisonKey) }
        }
    }
}

private extension Array where Element == String {
    func deduplicatedByNormalizedText() -> [String] {
        var seen = Set<String>()
        return filter { value in
            seen.insert(value.normalizedComparisonKey).inserted
        }
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
