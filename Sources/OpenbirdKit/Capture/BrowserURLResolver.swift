import AppKit
import Foundation

public struct BrowserURLResolver: Sendable {
    private static let cacheLifetime: TimeInterval = 15
    private static let cache = URLResolutionCache()
    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.microsoft.edgemac",
    ]
    private static let privateWindowTitleMarkers = [
        "new incognito tab",
        "private browsing",
        "private window",
    ]
    private static let privateWindowTextMarkers = [
        "browse inprivate",
        "inprivate browsing",
        "opened a private window",
        "private browsing",
        "you ve gone incognito",
    ]

    public init() {}

    public func currentURL(for bundleID: String, windowTitle: String) -> String? {
        guard isPrivateBrowsingActivity(bundleID: bundleID, windowTitle: windowTitle) == false else { return nil }

        let cacheKey = "\(bundleID)|\(windowTitle)"
        let now = Date()
        if let cached = cachedURL(for: cacheKey, now: now) {
            return cached.url
        }

        let resolvedURL: String?
        switch bundleID {
        case "com.apple.Safari":
            resolvedURL = runAppleScript("""
            tell application "Safari"
                if (count of windows) is 0 then return ""
                return URL of current tab of front window
            end tell
            """)
        case "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac":
            resolvedURL = runAppleScript("""
            tell application id "\(bundleID)"
                if (count of windows) is 0 then return ""
                return URL of active tab of front window
            end tell
            """)
        default:
            resolvedURL = nil
        }

        cacheResolvedURL(resolvedURL, for: cacheKey, now: now)
        return resolvedURL
    }

    func isBrowser(bundleID: String) -> Bool {
        Self.browserBundleIDs.contains(bundleID)
    }

    func isPrivateBrowsingActivity(
        bundleID: String,
        windowTitle: String,
        visibleText: String = ""
    ) -> Bool {
        guard isBrowser(bundleID: bundleID) else {
            return false
        }

        return hasPrivateWindowMarker(windowTitle, markers: Self.privateWindowTitleMarkers)
            || hasPrivateWindowMarker(visibleText, markers: Self.privateWindowTextMarkers)
    }

    private func hasPrivateWindowMarker(_ value: String, markers: [String]) -> Bool {
        let normalized = normalizedComparisonKey(for: value)
        guard normalized.isEmpty == false else {
            return false
        }

        return markers.contains(where: normalized.contains)
    }

    private func normalizedComparisonKey(for value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        let value = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == true ? nil : value
    }

    private func cachedURL(for key: String, now: Date) -> CacheEntry? {
        Self.cache.cachedURL(for: key, now: now, cacheLifetime: Self.cacheLifetime)
    }

    private func cacheResolvedURL(_ url: String?, for key: String, now: Date) {
        Self.cache.store(url: url, for: key, now: now, cacheLifetime: Self.cacheLifetime)
    }
}

private struct CacheEntry {
    let url: String?
    let resolvedAt: Date
}

private final class URLResolutionCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: CacheEntry] = [:]

    func cachedURL(for key: String, now: Date, cacheLifetime: TimeInterval) -> CacheEntry? {
        lock.lock()
        defer { lock.unlock() }

        guard let cached = cache[key],
              now.timeIntervalSince(cached.resolvedAt) <= cacheLifetime else {
            return nil
        }

        return cached
    }

    func store(url: String?, for key: String, now: Date, cacheLifetime: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        cache = cache.filter { now.timeIntervalSince($0.value.resolvedAt) <= cacheLifetime }
        cache[key] = CacheEntry(url: url, resolvedAt: now)
    }
}
