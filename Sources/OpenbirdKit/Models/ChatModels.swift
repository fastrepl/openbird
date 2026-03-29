import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

public struct Citation: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var eventID: String
    public var label: String

    public init(id: String = UUID().uuidString, eventID: String, label: String) {
        self.id = id
        self.eventID = eventID
        self.label = label
    }
}

public struct ChatThread: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var startDay: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        startDay: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startDay = startDay
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var threadID: String
    public var role: ChatRole
    public var content: String
    public var citations: [Citation]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        threadID: String,
        role: ChatRole,
        content: String,
        citations: [Citation] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.threadID = threadID
        self.role = role
        self.content = content
        self.citations = citations
        self.createdAt = createdAt
    }
}

public struct ChatQuery: Sendable {
    public var threadID: String
    public var question: String
    public var dateRange: ClosedRange<Date>
    public var appFilters: [String]
    public var topK: Int
    public var userMessageID: String
    public var assistantMessageID: String

    public init(
        threadID: String,
        question: String,
        dateRange: ClosedRange<Date>,
        appFilters: [String] = [],
        topK: Int = 8,
        userMessageID: String = UUID().uuidString,
        assistantMessageID: String = UUID().uuidString
    ) {
        self.threadID = threadID
        self.question = question
        self.dateRange = dateRange
        self.appFilters = appFilters
        self.topK = topK
        self.userMessageID = userMessageID
        self.assistantMessageID = assistantMessageID
    }
}

public enum PromptProfile: String, Codable, CaseIterable, Sendable {
    case concise
    case detailed
}

public struct JournalGenerationRequest: Sendable {
    public var date: Date
    public var timeZone: TimeZone
    public var maxSourceEvents: Int
    public var providerID: String?
    public var promptProfile: PromptProfile

    public init(
        date: Date,
        timeZone: TimeZone = .current,
        maxSourceEvents: Int = 80,
        providerID: String? = nil,
        promptProfile: PromptProfile = .concise
    ) {
        self.date = date
        self.timeZone = timeZone
        self.maxSourceEvents = maxSourceEvents
        self.providerID = providerID
        self.promptProfile = promptProfile
    }
}
