import Foundation

public actor OpenbirdStore {
    private let database: SQLiteDatabase
    private var pendingPreparedActivityDays: Set<String> = []
    private var dirtyPreparedActivityDays: Set<String> = []
    private var preparedActivityRefreshTask: Task<Void, Never>?

    public init(databaseURL: URL = OpenbirdPaths.databaseURL) throws {
        database = try SQLiteDatabase(url: databaseURL)
    }

    public func loadSettings() throws -> AppSettings {
        try database.loadSettings()
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try database.saveSettings(settings)
    }

    public func claimCollectorLease(ownerID: String, ownerName: String, now: Date, timeout: TimeInterval) throws -> Bool {
        try database.claimCollectorLease(ownerID: ownerID, ownerName: ownerName, now: now, timeout: timeout)
    }

    public func updateCollectorStatus(ownerID: String, status: String, heartbeat: Date) throws -> Bool {
        try database.updateCollectorStatus(ownerID: ownerID, status: status, heartbeat: heartbeat)
    }

    public func releaseCollectorLease(ownerID: String) throws {
        try database.releaseCollectorLease(ownerID: ownerID)
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
        let savedEvent = try database.saveActivityEvent(event)
        invalidatePreparedActivityDays(for: dayStringsCovered(by: savedEvent))
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
        let affectedDays = dayStrings(in: date...Date())
        try database.deleteEvents(since: date, affectedDays: affectedDays)
        try database.deletePreparedActivityEvents(for: affectedDays)
        invalidatePreparedActivityDays(for: affectedDays)
    }

    public func deleteAllEvents() throws {
        try database.deleteAllEvents()
        try database.deleteAllPreparedActivityEvents()
        pendingPreparedActivityDays.removeAll()
        dirtyPreparedActivityDays.removeAll()
    }

    public func saveEmbeddingChunk(id: String, eventID: String, providerID: String, model: String, vector: [Double], snippet: String) throws {
        try database.saveEmbeddingChunk(id: id, eventID: eventID, providerID: providerID, model: model, vector: vector, snippet: snippet)
    }

    public func loadEmbeddingChunks(providerID: String, model: String) throws -> [(eventID: String, vector: [Double], snippet: String)] {
        try database.loadEmbeddingChunks(providerID: providerID, model: model)
    }

    public func preparedActivityEvents(for date: Date) async throws -> [GroupedActivityEvent] {
        let day = OpenbirdDateFormatting.dayString(for: date)
        if dirtyPreparedActivityDays.contains(day) == false,
           let cached = try database.loadPreparedActivityEvents(for: day) {
            return cached
        }

        return try await rebuildPreparedActivityEvents(for: day, date: date)
    }

    public func prepareActivityEventsInBackground(for date: Date) {
        warmPreparedActivityDays(for: [OpenbirdDateFormatting.dayString(for: date)])
    }

    public func prepareRecentActivityEventsInBackground(endingAt date: Date = Date(), dayCount: Int) {
        warmPreparedActivityDays(for: recentDayStrings(endingAt: date, dayCount: dayCount))
    }

    private func rebuildPreparedActivityEvents(for day: String, date: Date) async throws -> [GroupedActivityEvent] {
        let rawEvents = try database.loadActivityEvents(
            in: Calendar.current.dayRange(for: date),
            includeExcluded: true
        )
        let groupedEvents = await Task.detached(priority: .utility) {
            ActivityEvidencePreprocessor.groupedMeaningfulEvents(from: rawEvents)
        }.value
        try database.savePreparedActivityEvents(groupedEvents, for: day)
        dirtyPreparedActivityDays.remove(day)
        return groupedEvents
    }

    private func invalidatePreparedActivityDays<S: Sequence>(for days: S) where S.Element == String {
        let normalizedDays = Set(days).filter { $0.isEmpty == false }
        guard normalizedDays.isEmpty == false else {
            return
        }

        pendingPreparedActivityDays.formUnion(normalizedDays)
        dirtyPreparedActivityDays.formUnion(normalizedDays)
        startPreparedActivityRefreshTaskIfNeeded()
    }

    private func warmPreparedActivityDays<S: Sequence>(for days: S) where S.Element == String {
        let normalizedDays = Set(days).filter { $0.isEmpty == false }
        guard normalizedDays.isEmpty == false else {
            return
        }

        let daysNeedingRefresh = normalizedDays.filter { day in
            if dirtyPreparedActivityDays.contains(day) {
                return true
            }
            return (try? database.loadPreparedActivityEvents(for: day)) == nil
        }

        guard daysNeedingRefresh.isEmpty == false else {
            return
        }

        pendingPreparedActivityDays.formUnion(daysNeedingRefresh)
        startPreparedActivityRefreshTaskIfNeeded()
    }

    private func startPreparedActivityRefreshTaskIfNeeded() {
        guard preparedActivityRefreshTask == nil else {
            return
        }

        preparedActivityRefreshTask = Task { [weak self] in
            await self?.runPreparedActivityRefreshLoop()
        }
    }

    private func runPreparedActivityRefreshLoop() async {
        while true {
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                break
            }

            let days = pendingPreparedActivityDays
            pendingPreparedActivityDays.removeAll()

            guard days.isEmpty == false else {
                break
            }

            for day in days.sorted() {
                guard let date = OpenbirdDateFormatting.date(fromDayString: day) else {
                    dirtyPreparedActivityDays.remove(day)
                    continue
                }

                do {
                    _ = try await rebuildPreparedActivityEvents(for: day, date: date)
                } catch {
                    pendingPreparedActivityDays.insert(day)
                }
            }
        }

        preparedActivityRefreshTask = nil
        if pendingPreparedActivityDays.isEmpty == false {
            startPreparedActivityRefreshTaskIfNeeded()
        }
    }

    private func dayStringsCovered(by event: ActivityEvent) -> Set<String> {
        dayStrings(in: event.startedAt...event.endedAt)
    }

    private func recentDayStrings(endingAt date: Date, dayCount: Int) -> Set<String> {
        guard dayCount > 0 else {
            return []
        }

        let calendar = Calendar.current
        let endOfWindow = calendar.startOfDay(for: date)
        guard let startOfWindow = calendar.date(byAdding: .day, value: -(dayCount - 1), to: endOfWindow) else {
            return [OpenbirdDateFormatting.dayString(for: endOfWindow)]
        }

        return dayStrings(in: startOfWindow...endOfWindow)
    }

    private func dayStrings(in range: ClosedRange<Date>) -> Set<String> {
        var dayStrings: Set<String> = []
        let calendar = Calendar.current
        var current = calendar.startOfDay(for: range.lowerBound)
        let last = calendar.startOfDay(for: range.upperBound)

        while current <= last {
            dayStrings.insert(OpenbirdDateFormatting.dayString(for: current))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                break
            }
            current = next
        }

        return dayStrings
    }
}
