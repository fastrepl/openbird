import CSQLite
import Foundation

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteValue: Sendable {
    case integer(Int64)
    case double(Double)
    case text(String)
    case null
}

public enum SQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)
    case bind(String)
    case generic(String)

    public var description: String {
        switch self {
        case .open(let message),
             .prepare(let message),
             .step(let message),
             .bind(let message),
             .generic(let message):
            return message
        }
    }
}

public final class SQLiteDatabase: @unchecked Sendable {
    private let handle: OpaquePointer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    public init(url: URL) throws {
        try OpenbirdPaths.ensureApplicationSupportDirectory()
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &db, flags, nil) != SQLITE_OK || db == nil {
            throw SQLiteError.open("Failed to open database at \(url.path)")
        }
        self.handle = db!
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try migrate()
        try seedDefaultsIfNeeded()
    }

    deinit {
        sqlite3_close(handle)
    }

    public func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteError.step(lastErrorMessage())
        }
    }

    public func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var rows: [[String: SQLiteValue]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }
            guard result == SQLITE_ROW else {
                throw SQLiteError.step(lastErrorMessage())
            }
            var row: [String: SQLiteValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    row[name] = .integer(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT:
                    row[name] = .double(sqlite3_column_double(statement, index))
                case SQLITE_TEXT:
                    row[name] = .text(String(cString: sqlite3_column_text(statement, index)))
                default:
                    row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    public func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    public func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw SQLiteError.generic("Invalid UTF-8 payload")
        }
        return try decoder.decode(type, from: data)
    }

    public func loadSettings() throws -> AppSettings {
        let rows = try query("SELECT key, value FROM app_settings;")
        guard rows.isEmpty == false else { return AppSettings() }
        var dict: [String: String] = [:]
        for row in rows {
            dict[row.stringValue(for: "key")] = row.stringValue(for: "value")
        }
        var settings = AppSettings()
        settings.capturePaused = dict["capturePaused"] == "true"
        settings.retentionDays = Int(dict["retentionDays"] ?? "14") ?? 14
        settings.activeProviderID = normalizeOptionalSetting(dict["activeProviderID"])
        if let heartbeat = normalizeOptionalSetting(dict["lastCollectorHeartbeat"]), let timestamp = Double(heartbeat) {
            settings.lastCollectorHeartbeat = Date(timeIntervalSince1970: timestamp)
        }
        settings.collectorStatus = dict["collectorStatus"] ?? "stopped"
        settings.collectorOwnerID = normalizeOptionalSetting(dict["collectorOwnerID"])
        settings.collectorOwnerName = normalizeOptionalSetting(dict["collectorOwnerName"])
        return settings
    }

    public func saveSettings(_ settings: AppSettings) throws {
        let values: [(String, String)] = [
            ("capturePaused", settings.capturePaused ? "true" : "false"),
            ("retentionDays", String(settings.retentionDays)),
            ("activeProviderID", settings.activeProviderID ?? ""),
            ("lastCollectorHeartbeat", settings.lastCollectorHeartbeat.map { String($0.timeIntervalSince1970) } ?? ""),
            ("collectorStatus", settings.collectorStatus),
            ("collectorOwnerID", settings.collectorOwnerID ?? ""),
            ("collectorOwnerName", settings.collectorOwnerName ?? ""),
        ]
        try execute("DELETE FROM app_settings;")
        for (key, value) in values {
            try execute(
                "INSERT INTO app_settings (key, value) VALUES (?, ?);",
                bindings: [.text(key), .text(value)]
            )
        }
    }

    public func claimCollectorLease(ownerID: String, ownerName: String, now: Date, timeout: TimeInterval) throws -> Bool {
        try withImmediateTransaction {
            var settings = try loadSettings()
            let currentOwnerID = settings.collectorOwnerID
            let heartbeatAge = settings.lastCollectorHeartbeat.map { now.timeIntervalSince($0) } ?? .infinity
            let hasFreshOwner = currentOwnerID != nil && heartbeatAge <= timeout
            if hasFreshOwner, currentOwnerID != ownerID {
                return false
            }
            if currentOwnerID != ownerID {
                settings.collectorStatus = settings.capturePaused ? "paused" : "idle"
            }
            settings.collectorOwnerID = ownerID
            settings.collectorOwnerName = ownerName
            settings.lastCollectorHeartbeat = now
            try saveSettings(settings)
            return true
        }
    }

    public func updateCollectorStatus(ownerID: String, status: String, heartbeat: Date) throws -> Bool {
        try withImmediateTransaction {
            var settings = try loadSettings()
            guard settings.collectorOwnerID == ownerID else {
                return false
            }
            settings.collectorStatus = status
            settings.lastCollectorHeartbeat = heartbeat
            try saveSettings(settings)
            return true
        }
    }

    public func releaseCollectorLease(ownerID: String) throws {
        try withImmediateTransaction {
            var settings = try loadSettings()
            guard settings.collectorOwnerID == ownerID else {
                return
            }
            settings.collectorOwnerID = nil
            settings.collectorOwnerName = nil
            settings.lastCollectorHeartbeat = nil
            settings.collectorStatus = settings.capturePaused ? "paused" : "stopped"
            try saveSettings(settings)
        }
    }

    public func saveProviderConfig(_ config: ProviderConfig) throws {
        let headers = try encode(config.customHeaders)
        try execute(
            """
            INSERT OR REPLACE INTO provider_configs
            (id, name, kind, base_url, api_key, chat_model, embedding_model, is_enabled, headers_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(config.id),
                .text(config.name),
                .text(config.kind.rawValue),
                .text(config.baseURL),
                .text(config.apiKey),
                .text(config.chatModel),
                .text(config.embeddingModel),
                .integer(config.isEnabled ? 1 : 0),
                .text(headers),
                .double(config.createdAt.timeIntervalSince1970),
                .double(config.updatedAt.timeIntervalSince1970),
            ]
        )
    }

    public func loadProviderConfigs() throws -> [ProviderConfig] {
        try query("SELECT * FROM provider_configs ORDER BY created_at ASC;").map { row in
            ProviderConfig(
                id: row.stringValue(for: "id"),
                name: row.stringValue(for: "name"),
                kind: ProviderKind(rawValue: row.stringValue(for: "kind")) ?? .ollama,
                baseURL: row.stringValue(for: "base_url"),
                apiKey: row.stringValue(for: "api_key"),
                chatModel: row.stringValue(for: "chat_model"),
                embeddingModel: row.stringValue(for: "embedding_model"),
                isEnabled: row.intValue(for: "is_enabled") == 1,
                customHeaders: (try? decode([String: String].self, from: row.stringValue(for: "headers_json"))) ?? [:],
                createdAt: Date(timeIntervalSince1970: row.doubleValue(for: "created_at")),
                updatedAt: Date(timeIntervalSince1970: row.doubleValue(for: "updated_at"))
            )
        }
    }

    public func saveExclusion(_ exclusion: ExclusionRule) throws {
        try execute(
            """
            INSERT OR REPLACE INTO exclusions (id, kind, pattern, is_enabled, created_at)
            VALUES (?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(exclusion.id),
                .text(exclusion.kind.rawValue),
                .text(exclusion.pattern),
                .integer(exclusion.isEnabled ? 1 : 0),
                .double(exclusion.createdAt.timeIntervalSince1970),
            ]
        )
    }

    public func loadExclusions() throws -> [ExclusionRule] {
        try query("SELECT * FROM exclusions ORDER BY created_at ASC;").map { row in
            ExclusionRule(
                id: row.stringValue(for: "id"),
                kind: ExclusionKind(rawValue: row.stringValue(for: "kind")) ?? .bundleID,
                pattern: row.stringValue(for: "pattern"),
                isEnabled: row.intValue(for: "is_enabled") == 1,
                createdAt: Date(timeIntervalSince1970: row.doubleValue(for: "created_at"))
            )
        }
    }

    public func deleteExclusion(id: String) throws {
        try execute("DELETE FROM exclusions WHERE id = ?;", bindings: [.text(id)])
    }

    public func saveActivityEvent(_ event: ActivityEvent) throws {
        try execute(
            """
            INSERT OR REPLACE INTO activity_events
            (id, started_at, ended_at, bundle_id, app_name, window_title, url, visible_text, source, content_hash, is_excluded)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(event.id),
                .double(event.startedAt.timeIntervalSince1970),
                .double(event.endedAt.timeIntervalSince1970),
                .text(event.bundleId),
                .text(event.appName),
                .text(event.windowTitle),
                event.url.map(SQLiteValue.text) ?? .null,
                .text(event.visibleText),
                .text(event.source),
                .text(event.contentHash),
                .integer(event.isExcluded ? 1 : 0),
            ]
        )
        try execute("DELETE FROM activity_events_fts WHERE id = ?;", bindings: [.text(event.id)])
        try execute(
            """
            INSERT INTO activity_events_fts (id, app_name, window_title, url, visible_text)
            VALUES (?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(event.id),
                .text(event.appName),
                .text(event.windowTitle),
                event.url.map(SQLiteValue.text) ?? .text(""),
                .text(event.visibleText),
            ]
        )
    }

    public func loadActivityEvents(in range: ClosedRange<Date>, includeExcluded: Bool = false) throws -> [ActivityEvent] {
        let sql = """
        SELECT * FROM activity_events
        WHERE started_at <= ? AND ended_at >= ?
        \(includeExcluded ? "" : "AND is_excluded = 0")
        ORDER BY started_at ASC;
        """
        return try query(
            sql,
            bindings: [
                .double(range.upperBound.timeIntervalSince1970),
                .double(range.lowerBound.timeIntervalSince1970),
            ]
        ).map(ActivityEvent.init(row:))
    }

    public func searchActivityEvents(
        query searchTerm: String,
        in range: ClosedRange<Date>,
        appFilters: [String],
        topK: Int
    ) throws -> [ActivityEvent] {
        guard let ftsQuery = makeFTSQuery(from: searchTerm) else {
            return try loadActivityEvents(in: range).suffix(topK).reversed()
        }

        var sql = """
        SELECT activity_events.*
        FROM activity_events
        JOIN activity_events_fts ON activity_events.id = activity_events_fts.id
        WHERE activity_events_fts MATCH ?
        AND activity_events.started_at <= ?
        AND activity_events.ended_at >= ?
        AND activity_events.is_excluded = 0
        """
        var bindings: [SQLiteValue] = [
            .text(ftsQuery),
            .double(range.upperBound.timeIntervalSince1970),
            .double(range.lowerBound.timeIntervalSince1970),
        ]
        if appFilters.isEmpty == false {
            sql += " AND activity_events.bundle_id IN (\(Array(repeating: "?", count: appFilters.count).joined(separator: ",")))"
            bindings += appFilters.map(SQLiteValue.text)
        }
        sql += " ORDER BY activity_events.started_at DESC LIMIT ?;"
        bindings.append(.integer(Int64(topK)))
        let results = try query(sql, bindings: bindings).map(ActivityEvent.init(row:))
        if results.isEmpty {
            return try loadActivityEvents(in: range).suffix(topK).reversed()
        }
        return results
    }

    public func saveJournal(_ journal: DailyJournal) throws {
        let sections = try encode(journal.sections)
        try execute(
            """
            INSERT OR REPLACE INTO daily_journals
            (id, day, markdown, sections_json, provider_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(journal.id),
                .text(journal.day),
                .text(journal.markdown),
                .text(sections),
                journal.providerID.map(SQLiteValue.text) ?? .null,
                .double(journal.createdAt.timeIntervalSince1970),
                .double(journal.updatedAt.timeIntervalSince1970),
            ]
        )
    }

    public func loadJournal(for day: String) throws -> DailyJournal? {
        try query("SELECT * FROM daily_journals WHERE day = ? LIMIT 1;", bindings: [.text(day)]).first.flatMap {
            DailyJournal(row: $0, database: self)
        }
    }

    public func saveThread(_ thread: ChatThread) throws {
        try execute(
            """
            INSERT OR REPLACE INTO chat_threads (id, title, start_day, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(thread.id),
                .text(thread.title),
                .text(thread.startDay),
                .double(thread.createdAt.timeIntervalSince1970),
                .double(thread.updatedAt.timeIntervalSince1970),
            ]
        )
    }

    public func loadThreads() throws -> [ChatThread] {
        try query("SELECT * FROM chat_threads ORDER BY updated_at DESC;").map { row in
            ChatThread(
                id: row.stringValue(for: "id"),
                title: row.stringValue(for: "title"),
                startDay: row.stringValue(for: "start_day"),
                createdAt: Date(timeIntervalSince1970: row.doubleValue(for: "created_at")),
                updatedAt: Date(timeIntervalSince1970: row.doubleValue(for: "updated_at"))
            )
        }
    }

    public func saveMessage(_ message: ChatMessage) throws {
        let citations = try encode(message.citations)
        try execute(
            """
            INSERT OR REPLACE INTO chat_messages (id, thread_id, role, content, citations_json, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(message.id),
                .text(message.threadID),
                .text(message.role.rawValue),
                .text(message.content),
                .text(citations),
                .double(message.createdAt.timeIntervalSince1970),
            ]
        )
    }

    public func loadMessages(threadID: String) throws -> [ChatMessage] {
        try query(
            "SELECT * FROM chat_messages WHERE thread_id = ? ORDER BY created_at ASC;",
            bindings: [.text(threadID)]
        ).map { row in
            ChatMessage(
                id: row.stringValue(for: "id"),
                threadID: row.stringValue(for: "thread_id"),
                role: ChatRole(rawValue: row.stringValue(for: "role")) ?? .assistant,
                content: row.stringValue(for: "content"),
                citations: (try? decode([Citation].self, from: row.stringValue(for: "citations_json"))) ?? [],
                createdAt: Date(timeIntervalSince1970: row.doubleValue(for: "created_at"))
            )
        }
    }

    public func deleteEvents(since date: Date) throws {
        let rows = try query("SELECT id FROM activity_events WHERE started_at >= ?;", bindings: [.double(date.timeIntervalSince1970)])
        for row in rows {
            try execute("DELETE FROM activity_events_fts WHERE id = ?;", bindings: [.text(row.stringValue(for: "id"))])
        }
        try execute("DELETE FROM activity_events WHERE started_at >= ?;", bindings: [.double(date.timeIntervalSince1970)])
    }

    public func deleteAllEvents() throws {
        try execute("DELETE FROM activity_events_fts;")
        try execute("DELETE FROM activity_events;")
        try execute("DELETE FROM daily_journals;")
        try execute("DELETE FROM embedding_chunks;")
    }

    public func saveEmbeddingChunk(id: String, eventID: String, providerID: String, model: String, vector: [Double], snippet: String) throws {
        let vectorString = try encode(vector)
        try execute(
            """
            INSERT OR REPLACE INTO embedding_chunks (id, event_id, provider_id, model, vector_json, snippet, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(id),
                .text(eventID),
                .text(providerID),
                .text(model),
                .text(vectorString),
                .text(snippet),
                .double(Date().timeIntervalSince1970),
            ]
        )
    }

    public func loadEmbeddingChunks(providerID: String) throws -> [(eventID: String, vector: [Double], snippet: String)] {
        try query(
            "SELECT event_id, vector_json, snippet FROM embedding_chunks WHERE provider_id = ?;",
            bindings: [.text(providerID)]
        ).compactMap { row in
            guard let vector = try? decode([Double].self, from: row.stringValue(for: "vector_json")) else { return nil }
            return (row.stringValue(for: "event_id"), vector, row.stringValue(for: "snippet"))
        }
    }

    private func migrate() throws {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS activity_events (
                id TEXT PRIMARY KEY,
                started_at REAL NOT NULL,
                ended_at REAL NOT NULL,
                bundle_id TEXT NOT NULL,
                app_name TEXT NOT NULL,
                window_title TEXT NOT NULL,
                url TEXT,
                visible_text TEXT NOT NULL,
                source TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                is_excluded INTEGER NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_activity_events_day
            ON activity_events(started_at, ended_at, is_excluded);
            """,
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS activity_events_fts
            USING fts5(id UNINDEXED, app_name, window_title, url, visible_text, tokenize='unicode61');
            """,
            """
            CREATE TABLE IF NOT EXISTS provider_configs (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                base_url TEXT NOT NULL,
                api_key TEXT NOT NULL,
                chat_model TEXT NOT NULL,
                embedding_model TEXT NOT NULL,
                is_enabled INTEGER NOT NULL DEFAULT 1,
                headers_json TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS exclusions (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                pattern TEXT NOT NULL,
                is_enabled INTEGER NOT NULL DEFAULT 1,
                created_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS daily_journals (
                id TEXT PRIMARY KEY,
                day TEXT UNIQUE NOT NULL,
                markdown TEXT NOT NULL,
                sections_json TEXT NOT NULL,
                provider_id TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS chat_threads (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                start_day TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS chat_messages (
                id TEXT PRIMARY KEY,
                thread_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                citations_json TEXT NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY(thread_id) REFERENCES chat_threads(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS embedding_chunks (
                id TEXT PRIMARY KEY,
                event_id TEXT NOT NULL,
                provider_id TEXT NOT NULL,
                model TEXT NOT NULL,
                vector_json TEXT NOT NULL,
                snippet TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            """,
        ]

        for statement in statements {
            try execute(statement)
        }
    }

    private func seedDefaultsIfNeeded() throws {
        let countRows = try query("SELECT COUNT(*) AS value FROM provider_configs;")
        let count = countRows.first?.intValue(for: "value") ?? 0
        guard count == 0 else { return }
        try saveProviderConfig(.defaultOllama)
        try saveProviderConfig(.defaultLMStudio)
        try saveSettings(AppSettings())
    }

    private func prepareStatement(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(lastErrorMessage())
        }
        return statement
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (index, value) in bindings.enumerated() {
            let parameter = Int32(index + 1)
            let result: Int32
            switch value {
            case .integer(let value):
                result = sqlite3_bind_int64(statement, parameter, value)
            case .double(let value):
                result = sqlite3_bind_double(statement, parameter, value)
            case .text(let value):
                result = sqlite3_bind_text(statement, parameter, value, -1, sqliteTransient)
            case .null:
                result = sqlite3_bind_null(statement, parameter)
            }
            guard result == SQLITE_OK else {
                throw SQLiteError.bind(lastErrorMessage())
            }
        }
    }

    private func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(handle))
    }

    private func withImmediateTransaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let value = try body()
            try execute("COMMIT;")
            return value
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func normalizeOptionalSetting(_ value: String?) -> String? {
        guard let value, value.isEmpty == false else { return nil }
        return value
    }

    private func makeFTSQuery(from rawQuery: String) -> String? {
        let tokens = rawQuery
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }

        guard tokens.isEmpty == false else { return nil }
        return tokens.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }.joined(separator: " OR ")
    }
}

private extension ActivityEvent {
    init(row: [String: SQLiteValue]) {
        self.init(
            id: row.stringValue(for: "id"),
            startedAt: Date(timeIntervalSince1970: row.doubleValue(for: "started_at")),
            endedAt: Date(timeIntervalSince1970: row.doubleValue(for: "ended_at")),
            bundleId: row.stringValue(for: "bundle_id"),
            appName: row.stringValue(for: "app_name"),
            windowTitle: row.stringValue(for: "window_title"),
            url: row.optionalStringValue(for: "url"),
            visibleText: row.stringValue(for: "visible_text"),
            source: row.stringValue(for: "source"),
            contentHash: row.stringValue(for: "content_hash"),
            isExcluded: row.intValue(for: "is_excluded") == 1
        )
    }
}

private extension DailyJournal {
    init?(row: [String: SQLiteValue], database: SQLiteDatabase) {
        guard let sectionsJSON = row.optionalStringValue(for: "sections_json"),
              let sections = try? database.decode([JournalSection].self, from: sectionsJSON)
        else {
            return nil
        }
        self.init(
            id: row.stringValue(for: "id"),
            day: row.stringValue(for: "day"),
            markdown: row.stringValue(for: "markdown"),
            sections: sections,
            providerID: row.optionalStringValue(for: "provider_id"),
            createdAt: Date(timeIntervalSince1970: row.doubleValue(for: "created_at")),
            updatedAt: Date(timeIntervalSince1970: row.doubleValue(for: "updated_at"))
        )
    }
}

private extension Dictionary where Key == String, Value == SQLiteValue {
    func stringValue(for key: String) -> String {
        switch self[key] {
        case .text(let value):
            return value
        case .integer(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .null, .none:
            return ""
        }
    }

    func optionalStringValue(for key: String) -> String? {
        let value = stringValue(for: key)
        return value.isEmpty ? nil : value
    }

    func intValue(for key: String) -> Int {
        switch self[key] {
        case .integer(let value):
            return Int(value)
        case .double(let value):
            return Int(value)
        case .text(let value):
            return Int(value) ?? 0
        case .null, .none:
            return 0
        }
    }

    func doubleValue(for key: String) -> TimeInterval {
        switch self[key] {
        case .integer(let value):
            return TimeInterval(value)
        case .double(let value):
            return TimeInterval(value)
        case .text(let value):
            return TimeInterval(value) ?? 0
        case .null, .none:
            return 0
        }
    }
}
