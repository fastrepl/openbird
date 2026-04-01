import Foundation
import Testing
@testable import OpenbirdKit

struct WindowSnapshotTests {
    @Test func fingerprintUsesFixedSizeDigest() {
        let snapshot = WindowSnapshot(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Openbird",
            url: "https://openbird.app",
            visibleText: String(repeating: "Working on memory compaction. ", count: 120)
        )

        let fingerprint = snapshot.fingerprint

        #expect(fingerprint.count == ActivityEventContentHash.compactLength)
        #expect(fingerprint != snapshot.visibleText)
        #expect(fingerprint == snapshot.fingerprint)
    }
}
