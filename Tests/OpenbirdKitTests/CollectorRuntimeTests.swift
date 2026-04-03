import Foundation
import Testing
@testable import OpenbirdKit

struct CollectorRuntimeTests {
    @Test func skipsCaptureForCurrentProcess() {
        let application = FrontmostApplicationContext(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            bundleID: "com.computelesscomputer.openbird",
            appName: "Openbird"
        )

        #expect(CollectorRuntime.shouldSkipCapture(for: application))
    }

    @Test func skipsCaptureForAnotherOpenbirdProcessWithSameBundleIdentifier() {
        let application = FrontmostApplicationContext(
            processIdentifier: 999_999,
            bundleID: "com.computelesscomputer.openbird",
            appName: "Openbird"
        )

        #expect(
            CollectorRuntime.shouldSkipCapture(
                for: application,
                currentProcessIdentifier: 111_111,
                currentBundleIdentifier: "com.computelesscomputer.openbird"
            )
        )
    }

    @Test func keepsCaptureEnabledForOtherApplications() {
        let application = FrontmostApplicationContext(
            processIdentifier: 999_999,
            bundleID: "com.apple.Safari",
            appName: "Safari"
        )

        #expect(
            CollectorRuntime.shouldSkipCapture(
                for: application,
                currentProcessIdentifier: 111_111,
                currentBundleIdentifier: "com.computelesscomputer.openbird"
            ) == false
        )
    }
}
