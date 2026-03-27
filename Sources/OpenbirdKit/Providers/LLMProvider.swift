import Foundation

public struct ChatTurn: Codable, Hashable, Sendable {
    public var role: ChatRole
    public var content: String

    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ProviderModelInfo: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var displayName: String

    public init(id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName ?? id
    }
}

public struct ProviderChatRequest: Sendable {
    public var messages: [ChatTurn]
    public var temperature: Double
    public var stream: Bool

    public init(messages: [ChatTurn], temperature: Double = 0.2, stream: Bool = false) {
        self.messages = messages
        self.temperature = temperature
        self.stream = stream
    }
}

public struct ProviderChatResponse: Sendable {
    public var content: String

    public init(content: String) {
        self.content = content
    }
}

public protocol LLMProvider: Sendable {
    var config: ProviderConfig { get }
    func listModels() async throws -> [ProviderModelInfo]
    func chat(request: ProviderChatRequest) async throws -> ProviderChatResponse
    func embed(texts: [String]) async throws -> [[Double]]
    func healthCheck() async throws -> Bool
}
