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

    @Test func mergesOverlappingEventsWithSameContentHash() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let now = Date()

        try await store.saveActivityEvent(
            ActivityEvent(
                id: "event-a",
                startedAt: now.addingTimeInterval(-120),
                endedAt: now.addingTimeInterval(-60),
                bundleId: "com.openai.codex",
                appName: "Codex",
                windowTitle: "Codex",
                url: nil,
                visibleText: "",
                source: "workspace",
                contentHash: "codex-hash",
                isExcluded: false
            )
        )
        try await store.saveActivityEvent(
            ActivityEvent(
                id: "event-b",
                startedAt: now.addingTimeInterval(-90),
                endedAt: now,
                bundleId: "com.openai.codex",
                appName: "Codex",
                windowTitle: "Codex",
                url: nil,
                visibleText: "",
                source: "accessibility",
                contentHash: "codex-hash",
                isExcluded: false
            )
        )

        let events = try await store.loadActivityEvents(in: Calendar.current.dayRange(for: now))

        #expect(events.count == 1)
        #expect(events.first?.id == "event-a")
        #expect(abs((events.first?.startedAt.timeIntervalSince1970 ?? 0) - now.addingTimeInterval(-120).timeIntervalSince1970) < 0.001)
        #expect(abs((events.first?.endedAt.timeIntervalSince1970 ?? 0) - now.timeIntervalSince1970) < 0.001)
        #expect(events.first?.source == "accessibility")
    }

    @Test func collectorLeaseBlocksSecondOwnerUntilHeartbeatExpires() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let now = Date()

        let firstClaim = try await store.claimCollectorLease(
            ownerID: "owner-a",
            ownerName: "/Applications/Openbird.app",
            now: now,
            timeout: 20
        )
        let secondClaim = try await store.claimCollectorLease(
            ownerID: "owner-b",
            ownerName: "/tmp/Openbird Dev.app",
            now: now.addingTimeInterval(5),
            timeout: 20
        )
        let settings = try await store.loadSettings()

        #expect(firstClaim)
        #expect(secondClaim == false)
        #expect(settings.collectorOwnerID == "owner-a")
        #expect(settings.collectorOwnerName == "/Applications/Openbird.app")
    }

    @Test func collectorLeaseCanBeRecoveredAfterHeartbeatExpires() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let now = Date()

        _ = try await store.claimCollectorLease(
            ownerID: "owner-a",
            ownerName: "/Applications/Openbird.app",
            now: now,
            timeout: 20
        )
        let recovered = try await store.claimCollectorLease(
            ownerID: "owner-b",
            ownerName: "/tmp/Openbird Dev.app",
            now: now.addingTimeInterval(25),
            timeout: 20
        )
        try await store.releaseCollectorLease(ownerID: "owner-b")
        let settings = try await store.loadSettings()

        #expect(recovered)
        #expect(settings.collectorOwnerID == nil)
        #expect(settings.collectorOwnerName == nil)
        #expect(settings.collectorStatus == "stopped")
    }

    @Test func savesSelectedProviderIDAlongsideProviderDrafts() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let provider = ProviderConfig(
            name: ProviderKind.anthropic.defaultName,
            kind: .anthropic,
            baseURL: ProviderKind.anthropic.defaultBaseURL,
            apiKey: "test-key",
            isEnabled: true
        )

        try await store.saveProviderConfig(provider)

        var settings = try await store.loadSettings()
        settings.selectedProviderID = provider.id
        try await store.saveSettings(settings)

        let reloadedSettings = try await store.loadSettings()
        let reloadedProviders = try await store.loadProviderConfigs()
        let savedProvider = reloadedProviders.first { $0.id == provider.id }

        #expect(reloadedSettings.selectedProviderID == provider.id)
        #expect(savedProvider?.kind == .anthropic)
        #expect(savedProvider?.apiKey == "test-key")
    }
}
