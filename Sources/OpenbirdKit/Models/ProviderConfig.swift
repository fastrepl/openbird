import Foundation

public enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case ollama
    case openAICompatible

    public var displayName: String {
        switch self {
        case .ollama:
            return "Ollama"
        case .openAICompatible:
            return "OpenAI-Compatible"
        }
    }
}

public struct ProviderConfig: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var kind: ProviderKind
    public var baseURL: String
    public var apiKey: String
    public var chatModel: String
    public var embeddingModel: String
    public var isEnabled: Bool
    public var customHeaders: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: ProviderKind,
        baseURL: String,
        apiKey: String = "",
        chatModel: String = "",
        embeddingModel: String = "",
        isEnabled: Bool = true,
        customHeaders: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.chatModel = chatModel
        self.embeddingModel = embeddingModel
        self.isEnabled = isEnabled
        self.customHeaders = customHeaders
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static let defaultOllama = ProviderConfig(
        name: "Local Ollama",
        kind: .ollama,
        baseURL: "http://127.0.0.1:11434",
        chatModel: "llama3.2",
        embeddingModel: "nomic-embed-text",
        isEnabled: false
    )

    public static let defaultLMStudio = ProviderConfig(
        name: "Local LM Studio",
        kind: .openAICompatible,
        baseURL: "http://127.0.0.1:1234/v1",
        chatModel: "local-model",
        embeddingModel: "text-embedding-model",
        isEnabled: false
    )
}
