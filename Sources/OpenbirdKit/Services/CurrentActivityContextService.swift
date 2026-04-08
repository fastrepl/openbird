import AppKit
import Foundation

public struct CurrentActivityContext: Equatable, Sendable {
    public let appName: String
    public let bundleID: String
    public let domain: String?

    public init(appName: String, bundleID: String, domain: String?) {
        self.appName = appName
        self.bundleID = bundleID
        self.domain = domain
    }
}

public struct CurrentActivityContextService: Sendable {
    private let snapshotter = AccessibilitySnapshotter()
    private let browserURLResolver = BrowserURLResolver()

    public init() {}

    public func currentContext() async -> CurrentActivityContext? {
        guard let application = await MainActor.run(body: { FrontmostApplicationContext.current() }) else {
            return nil
        }

        let shouldCollectVisibleText = browserURLResolver.isBrowser(bundleID: application.bundleID)
        let capturedSnapshot = await Task.detached(
            priority: .utility,
            operation: { @Sendable in
                snapshotter.snapshotFrontmostWindow(
                    for: application,
                    includeVisibleText: shouldCollectVisibleText
                )
            }
        ).value

        if let capturedSnapshot,
           browserURLResolver.isPrivateBrowsingActivity(
               bundleID: capturedSnapshot.bundleId,
               windowTitle: capturedSnapshot.windowTitle,
               visibleText: capturedSnapshot.visibleText
           ) {
            return nil
        }

        var snapshot = capturedSnapshot
        if snapshot == nil {
            guard shouldCollectVisibleText == false else {
                return nil
            }

            snapshot = WindowSnapshot(
                bundleId: application.bundleID,
                appName: application.appName,
                windowTitle: application.appName,
                url: nil,
                visibleText: "",
                source: "workspace"
            )
        }

        guard var snapshot else {
            return nil
        }

        if snapshot.url == nil {
            let bundleID = snapshot.bundleId
            let windowTitle = snapshot.windowTitle
            snapshot.url = await Task.detached(
                priority: .utility,
                operation: { @Sendable in
                    browserURLResolver.currentURL(
                        for: bundleID,
                        windowTitle: windowTitle
                    )
                }
            ).value
        }

        return CurrentActivityContext(
            appName: snapshot.appName,
            bundleID: snapshot.bundleId,
            domain: Self.normalizedDomain(from: snapshot.url)
        )
    }

    static func normalizedDomain(from url: String?) -> String? {
        guard let rawURL = url?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawURL.isEmpty == false
        else {
            return nil
        }

        let candidates = rawURL.contains("://") ? [rawURL] : [rawURL, "https://\(rawURL)"]
        for candidate in candidates {
            if let host = URLComponents(string: candidate)?.host?.lowercased(),
               host.isEmpty == false {
                return host
            }
        }

        return nil
    }
}
