import Foundation

public struct WindowSnapshot: Sendable {
    public var capturedAt: Date
    public var bundleId: String
    public var appName: String
    public var windowTitle: String
    public var url: String?
    public var visibleText: String
    public var source: String

    public init(
        capturedAt: Date = Date(),
        bundleId: String,
        appName: String,
        windowTitle: String,
        url: String?,
        visibleText: String,
        source: String = "accessibility"
    ) {
        self.capturedAt = capturedAt
        self.bundleId = bundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.visibleText = visibleText
        self.source = source
    }

    public var fingerprint: String {
        [bundleId, windowTitle, url ?? "", visibleText]
            .joined(separator: "|")
            .stableHash
    }

    public func asEvent(startedAt: Date, excluded: Bool) -> ActivityEvent {
        ActivityEvent(
            startedAt: startedAt,
            endedAt: capturedAt,
            bundleId: bundleId,
            appName: appName,
            windowTitle: excluded ? "Excluded content" : windowTitle,
            url: excluded ? nil : url,
            visibleText: excluded ? "" : visibleText,
            source: source,
            contentHash: fingerprint,
            isExcluded: excluded
        )
    }
}

private extension String {
    var stableHash: String {
        Data(utf8).base64EncodedString()
    }
}
