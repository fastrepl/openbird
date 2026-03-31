import Testing
@testable import OpenbirdKit

struct ExclusionEngineTests {
    @Test func matchesBundleAndDomainRules() {
        let engine = ExclusionEngine()
        let snapshot = WindowSnapshot(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Private stuff",
            url: "https://mail.google.com",
            visibleText: "Inbox"
        )

        let rules = [
            ExclusionRule(kind: .bundleID, pattern: "com.apple.Safari"),
            ExclusionRule(kind: .domain, pattern: "google.com"),
        ]

        #expect(engine.isExcluded(snapshot: snapshot, rules: rules))
    }

    @Test func matchesSubdomainsButNotLookalikeHosts() {
        let engine = ExclusionEngine()
        let matchingSnapshot = WindowSnapshot(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Docs",
            url: "https://docs.google.com/document/d/123",
            visibleText: "Draft"
        )
        let nonMatchingSnapshot = WindowSnapshot(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Search",
            url: "https://notgoogle.com?q=google.com",
            visibleText: "Results"
        )
        let rules = [ExclusionRule(kind: .domain, pattern: "google.com")]

        #expect(engine.isExcluded(snapshot: matchingSnapshot, rules: rules))
        #expect(engine.isExcluded(snapshot: nonMatchingSnapshot, rules: rules) == false)
    }

    @Test func matchesBundleAndDomainRulesWithoutSnapshotText() {
        let engine = ExclusionEngine()
        let rules = [
            ExclusionRule(kind: .bundleID, pattern: "com.apple.MobileSMS"),
            ExclusionRule(kind: .domain, pattern: "google.com"),
        ]

        #expect(engine.isExcluded(bundleID: "com.apple.MobileSMS", url: nil, rules: rules))
        #expect(engine.isExcluded(bundleID: "com.apple.Safari", url: "https://docs.google.com/document/d/123", rules: rules))
        #expect(engine.isExcluded(bundleID: "com.apple.Safari", url: "https://example.com", rules: rules) == false)
    }
}
