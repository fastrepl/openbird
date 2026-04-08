import Testing
@testable import OpenbirdKit

struct BrowserURLResolverTests {
    @Test func detectsPrivateBrowsingFromWindowTitle() {
        let resolver = BrowserURLResolver()

        #expect(
            resolver.isPrivateBrowsingActivity(
                bundleID: "com.apple.Safari",
                windowTitle: "Private Browsing"
            )
        )
        #expect(
            resolver.isPrivateBrowsingActivity(
                bundleID: "com.google.Chrome",
                windowTitle: "New Incognito Tab"
            )
        )
    }

    @Test func detectsPrivateBrowsingFromVisibleTextWhenTitleIsGeneric() {
        let resolver = BrowserURLResolver()

        #expect(
            resolver.isPrivateBrowsingActivity(
                bundleID: "com.apple.Safari",
                windowTitle: "Start Page",
                visibleText: "Private Browsing"
            )
        )
        #expect(
            resolver.isPrivateBrowsingActivity(
                bundleID: "com.microsoft.edgemac",
                windowTitle: "New Tab",
                visibleText: "Browse InPrivate"
            )
        )
    }

    @Test func doesNotTreatRegularPrivacyContentAsPrivateBrowsing() {
        let resolver = BrowserURLResolver()

        #expect(
            resolver.isPrivateBrowsingActivity(
                bundleID: "com.apple.Safari",
                windowTitle: "Private API docs"
            ) == false
        )
        #expect(
            resolver.isPrivateBrowsingActivity(
                bundleID: "com.google.Chrome",
                windowTitle: "How Incognito Mode Works"
            ) == false
        )
    }
}
