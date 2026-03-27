import Foundation

public enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case ollama
    case openAICompatible
    case openAI
    case anthropic
    case google
    case openRouter

    public var displayName: String {
        switch self {
        case .ollama:
            return "Ollama"
        case .openAICompatible:
            return "LM Studio / Compatible"
        case .openAI:
            return "OpenAI"
        case .anthropic:
            return "Anthropic"
        case .google:
            return "Google Gemini"
        case .openRouter:
            return "OpenRouter"
        }
    }

    public var defaultName: String {
        displayName
    }

    public var defaultBaseURL: String {
        switch self {
        case .ollama:
            return "http://127.0.0.1:11434/v1"
        case .openAICompatible:
            return "http://127.0.0.1:1234/v1"
        case .openAI:
            return "https://api.openai.com/v1"
        case .anthropic:
            return "https://api.anthropic.com/v1"
        case .google:
            return "https://generativelanguage.googleapis.com/v1beta"
        case .openRouter:
            return "https://openrouter.ai/api/v1"
        }
    }

    public var showsBaseURLField: Bool {
        switch self {
        case .ollama, .openAICompatible:
            return true
        case .openAI, .anthropic, .google, .openRouter:
            return false
        }
    }

    public var showsAPIKeyField: Bool {
        switch self {
        case .ollama:
            return false
        case .openAICompatible, .openAI, .anthropic, .google, .openRouter:
            return true
        }
    }

    public var requiresAPIKey: Bool {
        switch self {
        case .ollama, .openAICompatible:
            return false
        case .openAI, .anthropic, .google, .openRouter:
            return true
        }
    }

    public var supportsEmbeddings: Bool {
        switch self {
        case .anthropic:
            return false
        case .ollama, .openAICompatible, .openAI, .google, .openRouter:
            return true
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
        name: ProviderKind.ollama.defaultName,
        kind: .ollama,
        baseURL: ProviderKind.ollama.defaultBaseURL,
        chatModel: "llama3.2",
        embeddingModel: "nomic-embed-text",
        isEnabled: false
    )

    public static let defaultLMStudio = ProviderConfig(
        name: ProviderKind.openAICompatible.defaultName,
        kind: .openAICompatible,
        baseURL: ProviderKind.openAICompatible.defaultBaseURL,
        chatModel: "local-model",
        embeddingModel: "text-embedding-model",
        isEnabled: false
    )

    public static let defaultOpenAI = ProviderConfig(
        name: ProviderKind.openAI.defaultName,
        kind: .openAI,
        baseURL: ProviderKind.openAI.defaultBaseURL,
        isEnabled: false
    )

    public static let defaultAnthropic = ProviderConfig(
        name: ProviderKind.anthropic.defaultName,
        kind: .anthropic,
        baseURL: ProviderKind.anthropic.defaultBaseURL,
        isEnabled: false
    )

    public static let defaultGoogle = ProviderConfig(
        name: ProviderKind.google.defaultName,
        kind: .google,
        baseURL: ProviderKind.google.defaultBaseURL,
        isEnabled: false
    )

    public static let defaultOpenRouter = ProviderConfig(
        name: ProviderKind.openRouter.defaultName,
        kind: .openRouter,
        baseURL: ProviderKind.openRouter.defaultBaseURL,
        isEnabled: false
    )

    public static func defaultPreset(for kind: ProviderKind) -> ProviderConfig {
        switch kind {
        case .ollama:
            return .defaultOllama
        case .openAICompatible:
            return .defaultLMStudio
        case .openAI:
            return .defaultOpenAI
        case .anthropic:
            return .defaultAnthropic
        case .google:
            return .defaultGoogle
        case .openRouter:
            return .defaultOpenRouter
        }
    }
}
