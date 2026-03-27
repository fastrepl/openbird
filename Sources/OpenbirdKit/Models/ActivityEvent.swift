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

    public var excerpt: String {
        visibleText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(180)
            .description
    }
}
