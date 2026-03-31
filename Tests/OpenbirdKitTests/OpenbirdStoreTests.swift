import Foundation
import CSQLite
import Testing
@testable import OpenbirdKit

struct OpenbirdStoreTests {
    private struct LockConnection: @unchecked Sendable {
        let handle: OpaquePointer
    }

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

    @Test func partialDeleteRemovesOverlappingEventsAndDerivedArtifactsForAffectedDays() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let now = Date()
        let cutoff = now.addingTimeInterval(-3600)
        let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let previousDayString = OpenbirdDateFormatting.dayString(for: previousDay)
        let currentDayString = OpenbirdDateFormatting.dayString(for: now)

        let preservedEvent = ActivityEvent(
            id: "event-keep",
            startedAt: previousDay.addingTimeInterval(600),
            endedAt: previousDay.addingTimeInterval(900),
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Yesterday",
            url: "https://example.com/yesterday",
            visibleText: "Preserved event",
            source: "accessibility",
            contentHash: "event-keep",
            isExcluded: false
        )
        let deletedEvent = ActivityEvent(
            id: "event-delete",
            startedAt: cutoff.addingTimeInterval(-600),
            endedAt: cutoff.addingTimeInterval(300),
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Today",
            url: "https://example.com/today",
            visibleText: "Deleted event",
            source: "accessibility",
            contentHash: "event-delete",
            isExcluded: false
        )

        try await store.saveActivityEvent(preservedEvent)
        try await store.saveActivityEvent(deletedEvent)
        try await store.saveEmbeddingChunk(
            id: "embed-keep",
            eventID: preservedEvent.id,
            providerID: "provider",
            model: "embed-model",
            vector: [1, 0],
            snippet: "Preserved event"
        )
        try await store.saveEmbeddingChunk(
            id: "embed-delete",
            eventID: deletedEvent.id,
            providerID: "provider",
            model: "embed-model",
            vector: [0, 1],
            snippet: "Deleted event"
        )
        try await store.saveJournal(
            DailyJournal(
                day: previousDayString,
                markdown: "Yesterday journal",
                sections: [],
                providerID: nil
            )
        )
        try await store.saveJournal(
            DailyJournal(
                day: currentDayString,
                markdown: "Today journal",
                sections: [],
                providerID: nil
            )
        )

        let preservedThread = ChatThread(title: "Yesterday", startDay: previousDayString)
        let deletedThread = ChatThread(title: "Today", startDay: currentDayString)
        try await store.saveThread(preservedThread)
        try await store.saveThread(deletedThread)
        try await store.saveMessage(ChatMessage(threadID: preservedThread.id, role: .assistant, content: "Keep"))
        try await store.saveMessage(ChatMessage(threadID: deletedThread.id, role: .assistant, content: "Delete"))

        try await store.deleteEvents(since: cutoff)

        let remainingEvents = try await store.loadActivityEvents(in: previousDay...now, includeExcluded: true)
        let remainingEmbeddings = try await store.loadEmbeddingChunks(providerID: "provider", model: "embed-model")
        let remainingThreads = try await store.loadThreads()

        #expect(remainingEvents.map(\.id) == [preservedEvent.id])
        #expect(remainingEmbeddings.map(\.eventID) == [preservedEvent.id])
        #expect(try await store.loadJournal(for: previousDayString) != nil)
        #expect(try await store.loadJournal(for: currentDayString) == nil)
        #expect(remainingThreads.map(\.id) == [preservedThread.id])
        #expect(try await store.loadMessages(threadID: preservedThread.id).count == 1)
        #expect(try await store.loadMessages(threadID: deletedThread.id).isEmpty)
    }

    @Test func deleteAllRemovesChatHistoryAlongsideCapturedData() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let now = Date()
        let day = OpenbirdDateFormatting.dayString(for: now)
        let event = ActivityEvent(
            id: "event-delete-all",
            startedAt: now.addingTimeInterval(-60),
            endedAt: now,
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Delete all",
            url: "https://example.com/delete-all",
            visibleText: "Delete all content",
            source: "accessibility",
            contentHash: "event-delete-all",
            isExcluded: false
        )

        try await store.saveActivityEvent(event)
        try await store.saveEmbeddingChunk(
            id: "embed-delete-all",
            eventID: event.id,
            providerID: "provider",
            model: "embed-model",
            vector: [1, 1],
            snippet: "Delete all content"
        )
        try await store.saveJournal(
            DailyJournal(
                day: day,
                markdown: "Delete all journal",
                sections: [],
                providerID: nil
            )
        )
        let thread = ChatThread(title: "Delete all", startDay: day)
        try await store.saveThread(thread)
        try await store.saveMessage(ChatMessage(threadID: thread.id, role: .assistant, content: "Delete all chat"))

        try await store.deleteAllEvents()

        #expect(try await store.loadActivityEvents(in: Calendar.current.dayRange(for: now), includeExcluded: true).isEmpty)
        #expect(try await store.loadEmbeddingChunks(providerID: "provider", model: "embed-model").isEmpty)
        #expect(try await store.loadJournal(for: day) == nil)
        #expect(try await store.loadThreads().isEmpty)
        #expect(try await store.loadMessages(threadID: thread.id).isEmpty)
    }

    @Test func preparedActivityEventsGroupNoisyAccessibilityLogs() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let start = Date(timeIntervalSince1970: 1_720_000_000)

        let events = [
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(30),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice Profile 9:31 PM See you there Enter a message Search Voice Call Video Call Menu",
                source: "accessibility",
                contentHash: "chat-a",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(31),
                endedAt: start.addingTimeInterval(60),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice 9:39 PM See you there tomorrow Enter a message Search Menu",
                source: "accessibility",
                contentHash: "chat-b",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(90),
                endedAt: start.addingTimeInterval(180),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice 10:23 PM Shared the pickup plan",
                source: "accessibility",
                contentHash: "chat-c",
                isExcluded: false
            ),
        ]

        for event in events {
            try await store.saveActivityEvent(event)
        }

        let grouped = try await store.preparedActivityEvents(for: start)

        #expect(grouped.count == 1)
        #expect(grouped.first?.sourceEventIDs.count == 3)
        #expect(grouped.first?.sourceEventCount == 3)
        #expect(grouped.first?.excerpt.contains("Enter a message") == false)
        #expect(grouped.first?.excerpt.contains("Voice Call") == false)
    }

    @Test func preparedActivityEventsRefreshWhenNewLogsArrive() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let start = Date(timeIntervalSince1970: 1_720_000_000)

        try await store.saveActivityEvent(
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(30),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice See you there",
                source: "accessibility",
                contentHash: "chat-a",
                isExcluded: false
            )
        )

        let initial = try await store.preparedActivityEvents(for: start)
        #expect(initial.count == 1)
        #expect(initial.first?.sourceEventCount == 1)

        try await store.saveActivityEvent(
            ActivityEvent(
                startedAt: start.addingTimeInterval(31),
                endedAt: start.addingTimeInterval(60),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice Shared the pickup plan",
                source: "accessibility",
                contentHash: "chat-b",
                isExcluded: false
            )
        )

        let refreshed = try await store.preparedActivityEvents(for: start)
        #expect(refreshed.count == 1)
        #expect(refreshed.first?.sourceEventCount == 2)
    }

    @Test func backgroundPrepareKeepsFreshPreparedActivityCache() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let start = Date(timeIntervalSince1970: 1_720_000_000)
        let day = OpenbirdDateFormatting.dayString(for: start)

        try await store.saveActivityEvent(
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(30),
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: "Openbird",
                url: "https://openbird.app",
                visibleText: "Reviewed the Openbird homepage",
                source: "accessibility",
                contentHash: "safari-home",
                isExcluded: false
            )
        )

        try await Task.sleep(for: .milliseconds(650))
        let initialUpdatedAt = try preparedActivityUpdatedAt(at: databaseURL, day: day)

        #expect(initialUpdatedAt != nil)

        await store.prepareActivityEventsInBackground(for: start)
        try await Task.sleep(for: .milliseconds(650))

        let refreshedUpdatedAt = try preparedActivityUpdatedAt(at: databaseURL, day: day)
        #expect(refreshedUpdatedAt == initialUpdatedAt)
    }

    @Test func backgroundPrepareRecentDaysBackfillsMissingPreparedActivityCache() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let end = Date(timeIntervalSince1970: 1_720_086_400)
        let previousDayEventStart = end.addingTimeInterval(-(24 * 3600))
        let previousDay = OpenbirdDateFormatting.dayString(for: previousDayEventStart)

        try await store.saveActivityEvent(
            ActivityEvent(
                startedAt: previousDayEventStart,
                endedAt: previousDayEventStart.addingTimeInterval(45),
                bundleId: "com.microsoft.VSCode",
                appName: "VS Code",
                windowTitle: "openbird",
                url: nil,
                visibleText: "Refined grouped activity cache invalidation",
                source: "accessibility",
                contentHash: "vscode-cache",
                isExcluded: false
            )
        )

        try await Task.sleep(for: .milliseconds(650))
        try deleteAllPreparedActivityDays(at: databaseURL)
        #expect(try preparedActivityUpdatedAt(at: databaseURL, day: previousDay) == nil)

        await store.prepareRecentActivityEventsInBackground(endingAt: end, dayCount: 2)
        try await Task.sleep(for: .milliseconds(650))

        #expect(try preparedActivityUpdatedAt(at: databaseURL, day: previousDay) != nil)
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

    @Test func loadsEmbeddingChunksForTheRequestedModelOnly() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)

        try await store.saveEmbeddingChunk(
            id: "provider-event-1",
            eventID: "event-1",
            providerID: "provider",
            model: "text-embedding-3-small",
            vector: [0.1, 0.2],
            snippet: "first"
        )
        try await store.saveEmbeddingChunk(
            id: "provider-event-2",
            eventID: "event-2",
            providerID: "provider",
            model: "text-embedding-3-large",
            vector: [0.3, 0.4],
            snippet: "second"
        )

        let smallModelChunks = try await store.loadEmbeddingChunks(
            providerID: "provider",
            model: "text-embedding-3-small"
        )

        #expect(smallModelChunks.count == 1)
        #expect(smallModelChunks.first?.eventID == "event-1")
        #expect(smallModelChunks.first?.snippet == "first")
    }

    @Test func surfacesSQLiteMessagesThroughLocalizedDescription() {
        let error = SQLiteError.step("database is locked")
        #expect(error.localizedDescription == "database is locked")
    }

    @Test func waitsForTransientWriteLocksBeforeSavingJournal() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)

        var lockHandle: OpaquePointer?
        #expect(sqlite3_open_v2(databaseURL.path, &lockHandle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK)
        guard let lockHandle else {
            Issue.record("Failed to open lock connection")
            return
        }
        let lockConnection = LockConnection(handle: lockHandle)

        #expect(sqlite3_exec(lockConnection.handle, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(lockConnection.handle, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK)

        let unlockTask = Task.detached {
            try? await Task.sleep(for: .milliseconds(150))
            sqlite3_exec(lockConnection.handle, "COMMIT;", nil, nil, nil)
        }

        let journal = DailyJournal(
            day: OpenbirdDateFormatting.dayString(for: Date()),
            markdown: "Summary",
            sections: [],
            providerID: nil
        )
        try await store.saveJournal(journal)
        _ = await unlockTask.value
        sqlite3_close(lockConnection.handle)

        let reloaded = try await store.loadJournal(for: journal.day)
        #expect(reloaded?.markdown == "Summary")
    }

    private func preparedActivityUpdatedAt(at databaseURL: URL, day: String) throws -> TimeInterval? {
        let database = try SQLiteDatabase(url: databaseURL)
        let rows = try database.query(
            "SELECT updated_at FROM prepared_activity_days WHERE day = ? LIMIT 1;",
            bindings: [.text(day)]
        )
        guard let value = rows.first?["updated_at"] else {
            return nil
        }

        switch value {
        case .integer(let timestamp):
            return TimeInterval(timestamp)
        case .double(let timestamp):
            return timestamp
        case .text(let timestamp):
            return TimeInterval(timestamp)
        case .null:
            return nil
        }
    }

    private func deleteAllPreparedActivityDays(at databaseURL: URL) throws {
        let database = try SQLiteDatabase(url: databaseURL)
        try database.deleteAllPreparedActivityEvents()
    }
}
