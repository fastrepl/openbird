import Foundation
import OpenbirdKit
import Testing
@testable import OpenbirdApp

struct AppModelUpdateCheckTests {
    @Test func showsRestartStatusAfterInstallerIsReady() {
        #expect(
            AppModel.updateStatusText(
                appVersionAvailable: true,
                isInstallingUpdate: false,
                isUpdateRestartPending: true,
                availableUpdateVersion: "0.2.0",
                isCheckingForUpdates: false,
                updateStatusMessage: "Restart Openbird to finish updating to 0.2.0."
            ) == "Restart Openbird to finish update"
        )
    }

    @Test func prefersInstallingStatusUntilRestartIsPending() {
        #expect(
            AppModel.updateStatusText(
                appVersionAvailable: true,
                isInstallingUpdate: true,
                isUpdateRestartPending: false,
                availableUpdateVersion: "0.2.0",
                isCheckingForUpdates: false,
                updateStatusMessage: "Installing Openbird 0.2.0…"
            ) == "Installing update..."
        )
    }

    @Test func allowsAutomaticChecksWhenAppVersionExistsAndNoRecentCheckRan() {
        #expect(
            AppModel.shouldAutomaticallyCheckForUpdates(
                appVersion: "0.1.0",
                isUpdateCheckInFlight: false,
                availableUpdate: nil,
                lastCheckDate: nil,
                now: Date(timeIntervalSinceReferenceDate: 1_000),
                automaticUpdateCheckInterval: 60
            )
        )

        #expect(
            AppModel.shouldAutomaticallyCheckForUpdates(
                appVersion: "0.1.0",
                isUpdateCheckInFlight: false,
                availableUpdate: nil,
                lastCheckDate: Date(timeIntervalSinceReferenceDate: 900),
                now: Date(timeIntervalSinceReferenceDate: 1_000),
                automaticUpdateCheckInterval: 60
            )
        )
    }

    @Test func skipsAutomaticChecksWhenThePreviousCheckIsStillFresh() {
        #expect(
            AppModel.shouldAutomaticallyCheckForUpdates(
                appVersion: "0.1.0",
                isUpdateCheckInFlight: false,
                availableUpdate: nil,
                lastCheckDate: Date(timeIntervalSinceReferenceDate: 950),
                now: Date(timeIntervalSinceReferenceDate: 1_000),
                automaticUpdateCheckInterval: 60
            ) == false
        )
    }

    @Test func skipsAutomaticChecksWhenUpdateStateAlreadyHasWorkInFlight() {
        let update = AppUpdate(
            version: "0.2.0",
            releaseURL: URL(string: "https://example.com/release")!,
            downloadURL: URL(string: "https://example.com/release.dmg")!
        )

        #expect(
            AppModel.shouldAutomaticallyCheckForUpdates(
                appVersion: nil,
                isUpdateCheckInFlight: false,
                availableUpdate: nil,
                lastCheckDate: nil,
                now: Date(timeIntervalSinceReferenceDate: 1_000),
                automaticUpdateCheckInterval: 60
            ) == false
        )

        #expect(
            AppModel.shouldAutomaticallyCheckForUpdates(
                appVersion: "0.1.0",
                isUpdateCheckInFlight: true,
                availableUpdate: nil,
                lastCheckDate: nil,
                now: Date(timeIntervalSinceReferenceDate: 1_000),
                automaticUpdateCheckInterval: 60
            ) == false
        )

        #expect(
            AppModel.shouldAutomaticallyCheckForUpdates(
                appVersion: "0.1.0",
                isUpdateCheckInFlight: false,
                availableUpdate: update,
                lastCheckDate: nil,
                now: Date(timeIntervalSinceReferenceDate: 1_000),
                automaticUpdateCheckInterval: 60
            ) == false
        )
    }
}
