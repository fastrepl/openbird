import Foundation

public actor OpenbirdStore {
    private let database: SQLiteDatabase

    public init(databaseURL: URL = OpenbirdPaths.databaseURL) throws {
        database = try SQLiteDatabase(url: databaseURL)
    }

    public func loadSettings() throws -> AppSettings {
        try database.loadSettings()
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try database.saveSettings(settings)
    }

    public func loadProviderConfigs() throws -> [ProviderConfig] {
        try database.loadProviderConfigs()
    }

    public func saveProviderConfig(_ config: ProviderConfig) throws {
        try database.saveProviderConfig(config)
    }

    public func loadExclusions() throws -> [ExclusionRule] {
        try database.loadExclusions()
    }

    public func saveExclusion(_ exclusion: ExclusionRule) throws {
        try database.saveExclusion(exclusion)
    }

    public func deleteExclusion(id: String) throws {
        try database.deleteExclusion(id: id)
    }

    public func saveActivityEvent(_ event: ActivityEvent) throws {
        try database.saveActivityEvent(event)
    }

    public func loadActivityEvents(in range: ClosedRange<Date>, includeExcluded: Bool = false) throws -> [ActivityEvent] {
        try database.loadActivityEvents(in: range, includeExcluded: includeExcluded)
    }

    public func searchActivityEvents(
        query: String,
        in range: ClosedRange<Date>,
        appFilters: [String] = [],
        topK: Int = 8
    ) throws -> [ActivityEvent] {
        try database.searchActivityEvents(query: query, in: range, appFilters: appFilters, topK: topK)
    }

    public func loadJournal(for day: String) throws -> DailyJournal? {
        try database.loadJournal(for: day)
    }

    public func saveJournal(_ journal: DailyJournal) throws {
        try database.saveJournal(journal)
    }

    public func loadThreads() throws -> [ChatThread] {
        try database.loadThreads()
    }

    public func saveThread(_ thread: ChatThread) throws {
        try database.saveThread(thread)
    }

    public func loadMessages(threadID: String) throws -> [ChatMessage] {
        try database.loadMessages(threadID: threadID)
    }

    public func saveMessage(_ message: ChatMessage) throws {
        try database.saveMessage(message)
    }

    public func deleteEvents(since date: Date) throws {
        try database.deleteEvents(since: date)
    }

    public func deleteAllEvents() throws {
        try database.deleteAllEvents()
    }

    public func saveEmbeddingChunk(id: String, eventID: String, providerID: String, model: String, vector: [Double], snippet: String) throws {
        try database.saveEmbeddingChunk(id: id, eventID: eventID, providerID: providerID, model: model, vector: vector, snippet: snippet)
    }

    public func loadEmbeddingChunks(providerID: String) throws -> [(eventID: String, vector: [Double], snippet: String)] {
        try database.loadEmbeddingChunks(providerID: providerID)
    }
}
