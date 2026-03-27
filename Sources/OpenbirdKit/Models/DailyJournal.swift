import Foundation

public struct JournalSection: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var heading: String
    public var timeRange: String
    public var bullets: [String]
    public var sourceEventIDs: [String]

    public init(
        id: String = UUID().uuidString,
        heading: String,
        timeRange: String,
        bullets: [String],
        sourceEventIDs: [String]
    ) {
        self.id = id
        self.heading = heading
        self.timeRange = timeRange
        self.bullets = bullets
        self.sourceEventIDs = sourceEventIDs
    }
}

public struct DailyJournal: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var day: String
    public var markdown: String
    public var sections: [JournalSection]
    public var providerID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        day: String,
        markdown: String,
        sections: [JournalSection],
        providerID: String?,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.day = day
        self.markdown = markdown
        self.sections = sections
        self.providerID = providerID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
