import Foundation

public struct ActivityEvent: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var startedAt: Date
    public var endedAt: Date
    public var bundleId: String
    public var appName: String
    public var windowTitle: String
    public var url: String?
    public var visibleText: String
    public var source: String
    public var contentHash: String
    public var isExcluded: Bool

    public init(
        id: String = UUID().uuidString,
        startedAt: Date,
        endedAt: Date,
        bundleId: String,
        appName: String,
        windowTitle: String,
        url: String?,
        visibleText: String,
        source: String,
        contentHash: String,
        isExcluded: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.bundleId = bundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.visibleText = visibleText
        self.source = source
        self.contentHash = contentHash
        self.isExcluded = isExcluded
    }

    public var displayTitle: String {
        windowTitle.isEmpty ? appName : windowTitle
    }

    public var detailTitle: String? {
        let trimmed = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.normalizedComparisonKey != appName.normalizedComparisonKey
        else {
            return nil
        }
        return trimmed
    }

    public var excerpt: String {
        let collapsed = visibleText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = collapsed.normalizedComparisonKey
        guard collapsed.isEmpty == false,
              normalized != appName.normalizedComparisonKey,
              normalized != windowTitle.normalizedComparisonKey
        else {
            return ""
        }
        return collapsed.prefix(180).description
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
