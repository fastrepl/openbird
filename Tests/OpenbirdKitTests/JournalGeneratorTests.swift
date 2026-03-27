import Foundation
import Testing
@testable import OpenbirdKit

struct JournalGeneratorTests {
    @Test func generatesSectionsFromSyntheticEvents() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let generator = JournalGenerator(store: store)

        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
        let events = [
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(600),
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: "Investor Portal",
                url: "https://example.com",
                visibleText: "Reviewed startup profiles",
                source: "accessibility",
                contentHash: "a",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(700),
                endedAt: start.addingTimeInterval(1300),
                bundleId: "com.microsoft.VSCode",
                appName: "VS Code",
                windowTitle: "openbird",
                url: nil,
                visibleText: "Implemented journaling",
                source: "accessibility",
                contentHash: "b",
                isExcluded: false
            ),
        ]

        for event in events {
            try await store.saveActivityEvent(event)
        }

        let journal = try await generator.generate(
            request: JournalGenerationRequest(
                date: start,
                providerID: nil
            )
        )

        #expect(journal.sections.count >= 1)
        #expect(journal.markdown.contains("Review"))
    }
}
