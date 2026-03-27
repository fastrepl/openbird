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
}
