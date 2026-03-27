import Foundation
import Testing
@testable import OpenbirdKit

struct OpenbirdStoreTests {
    @Test func savesAndSearchesActivityEvents() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)

        let now = Date()
        try await store.saveActivityEvent(
            ActivityEvent(
                startedAt: now.addingTimeInterval(-300),
                endedAt: now,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: "YC Demo Day",
                url: "https://bookface.ycombinator.com",
                visibleText: "Read YC W26 demo day company profiles",
                source: "accessibility",
                contentHash: "hash-1",
                isExcluded: false
            )
        )

        let results = try await store.searchActivityEvents(
            query: "demo day",
            in: Calendar.current.dayRange(for: now),
            topK: 5
        )

        #expect(results.count == 1)
        #expect(results.first?.appName == "Safari")
    }

    @Test func searchesNaturalLanguageWithPunctuation() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let now = Date()

        try await store.saveActivityEvent(
            ActivityEvent(
                startedAt: now.addingTimeInterval(-180),
                endedAt: now,
                bundleId: "com.microsoft.VSCode",
                appName: "VS Code",
                windowTitle: "openbird",
                url: nil,
                visibleText: "Implemented local chat retrieval for activity review",
                source: "accessibility",
                contentHash: "hash-2",
                isExcluded: false
            )
        )

        let results = try await store.searchActivityEvents(
            query: "What have I been doing in the last few minutes?",
            in: Calendar.current.dayRange(for: now),
            topK: 5
        )

        #expect(results.isEmpty == false)
        #expect(results.first?.appName == "VS Code")
    }
}
