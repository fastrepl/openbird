import Foundation

public enum DataDeletionScope: String, CaseIterable, Sendable {
    case lastHour
    case lastDay
    case all
}

public actor RetentionService {
    private let store: OpenbirdStore

    public init(store: OpenbirdStore) {
        self.store = store
    }

    public func delete(scope: DataDeletionScope) async throws {
        switch scope {
        case .lastHour:
            try await store.deleteEvents(since: Date().addingTimeInterval(-3600))
        case .lastDay:
            try await store.deleteEvents(since: Date().addingTimeInterval(-(24 * 3600)))
        case .all:
            try await store.deleteAllEvents()
        }
    }
}
