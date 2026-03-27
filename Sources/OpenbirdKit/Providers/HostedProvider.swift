import Foundation

public struct HostedProvider: LLMProvider {
    public let config: ProviderConfig
    private let session: URLSession

    public init(config: ProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func listModels() async throws -> [ProviderModelInfo] {
        switch config.kind {
        case .openAICompatible, .openAI, .openRouter:
            let response: OpenAIModelsResponse = try await performRequest(path: "/models")
            return response.data.map { ProviderModelInfo(id: $0.id) }
        case .anthropic:
            let response: AnthropicModelsResponse = try await performRequest(path: "/models")
            return response.data.map { ProviderModelInfo(id: $0.id, displayName: $0.displayName ?? $0.id) }
        case .google:
            let response: GoogleModelsResponse = try await performRequest(path: "/models")
            return response.models.map {
                let id = Self.googleModelID(from: $0.name)
                return ProviderModelInfo(id: id, displayName: $0.displayName ?? id)
            }
        case .ollama:
            throw HostedProviderError.unsupportedProvider
        }
    }

    public func chat(request: ProviderChatRequest) async throws -> ProviderChatResponse {
        switch config.kind {
        case .openAICompatible, .openAI, .openRouter:
            let payload = OpenAIChatRequest(
                model: config.chatModel,
                messages: request.messages.map { .init(role: $0.role.rawValue, content: $0.content) },
                temperature: request.temperature,
                stream: request.stream
            )
            let response: OpenAIChatResponse = try await performRequest(
                path: "/chat/completions",
                method: "POST",
                body: payload
            )
            return ProviderChatResponse(content: response.choices.first?.message.content ?? "")
        case .anthropic:
            let prepared = preparedMessages(for: request.messages)
            let payload = AnthropicChatRequest(
                model: config.chatModel,
                system: prepared.system,
                messages: prepared.messages.map { .init(role: $0.role.rawValue, content: $0.content) },
                temperature: request.temperature,
                maxTokens: 4096
            )
            let response: AnthropicChatResponse = try await performRequest(
                path: "/messages",
                method: "POST",
                body: payload
            )
            let content = response.content
                .filter { $0.type == "text" }
                .compactMap(\.text)
                .joined(separator: "\n\n")
            return ProviderChatResponse(content: content)
        case .google:
            let prepared = preparedMessages(for: request.messages)
            let payload = GoogleGenerateContentRequest(
                systemInstruction: prepared.system.map {
                    .init(parts: [.init(text: $0)])
                },
                contents: prepared.messages.map {
                    .init(role: $0.role == .assistant ? "model" : "user", parts: [.init(text: $0.content)])
                }
            )
            let response: GoogleGenerateContentResponse = try await performRequest(
                path: "/\(Self.googleModelResourceName(for: config.chatModel)):generateContent",
                method: "POST",
                body: payload
            )
            let content = response.candidates.first?.content.parts
                .compactMap(\.text)
                .joined(separator: "\n\n") ?? ""
            return ProviderChatResponse(content: content)
        case .ollama:
            throw HostedProviderError.unsupportedProvider
        }
    }

    public func embed(texts: [String]) async throws -> [[Double]] {
        guard config.embeddingModel.isEmpty == false else { return [] }

        switch config.kind {
        case .openAICompatible, .openAI, .openRouter:
            let payload = OpenAIEmbedRequest(model: config.embeddingModel, input: texts)
            let response: OpenAIEmbedResponse = try await performRequest(
                path: "/embeddings",
                method: "POST",
                body: payload
            )
            return response.data.sorted(by: { $0.index < $1.index }).map(\.embedding)
        case .google:
            var embeddings: [[Double]] = []
            for text in texts {
                let payload = GoogleEmbedContentRequest(content: .init(parts: [.init(text: text)]))
                let response: GoogleEmbedContentResponse = try await performRequest(
                    path: "/\(Self.googleModelResourceName(for: config.embeddingModel)):embedContent",
                    method: "POST",
                    body: payload
                )
                embeddings.append(response.embedding.values)
            }
            return embeddings
        case .anthropic:
            return []
        case .ollama:
            throw HostedProviderError.unsupportedProvider
        }
    }

    public func healthCheck() async throws -> Bool {
        _ = try await listModels()
        return true
    }

    private func performRequest<Response: Decodable>(
        path: String,
        method: String = "GET",
        bodyData: Data? = nil
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: method, bodyData: bodyData)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func performRequest<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        try await performRequest(path: path, method: method, bodyData: try JSONEncoder().encode(body))
    }

    private func makeRequest(path: String, method: String, bodyData: Data?) throws -> URLRequest {
        guard let baseURL = URL(string: config.baseURL) else {
            throw URLError(.badURL)
        }
        if config.kind.requiresAPIKey && config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw HostedProviderError.missingAPIKey(config.kind.displayName)
        }

        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method

        for (key, value) in requestHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let bodyData {
            request.httpBody = bodyData
        }
        return request
    }

    private func requestHeaders() -> [String: String] {
        var headers = [
            "Content-Type": "application/json",
        ]

        switch config.kind {
        case .openAICompatible, .openAI:
            if config.apiKey.isEmpty == false {
                headers["Authorization"] = "Bearer \(config.apiKey)"
            }
        case .openRouter:
            if config.apiKey.isEmpty == false {
                headers["Authorization"] = "Bearer \(config.apiKey)"
            }
            headers["HTTP-Referer"] = "https://openbird.app"
            headers["X-Title"] = "Openbird"
        case .anthropic:
            headers["x-api-key"] = config.apiKey
            headers["anthropic-version"] = "2023-06-01"
        case .google:
            headers["x-goog-api-key"] = config.apiKey
        case .ollama:
            break
        }

        for (key, value) in config.customHeaders {
            headers[key] = value
        }

        return headers
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed"
            throw NSError(domain: "HostedProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func preparedMessages(for messages: [ChatTurn]) -> (system: String?, messages: [ChatTurn]) {
        let system = messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nonSystem = messages.filter { $0.role != .system }
        return (system.isEmpty ? nil : system, nonSystem)
    }

    private static func googleModelID(from value: String) -> String {
        value.hasPrefix("models/") ? String(value.dropFirst("models/".count)) : value
    }

    private static func googleModelResourceName(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("models/") {
            return trimmed
        }
        return "models/\(trimmed)"
    }
}

private enum HostedProviderError: LocalizedError {
    case missingAPIKey(String)
    case unsupportedProvider

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Enter a \(provider) API key."
        case .unsupportedProvider:
            return "Unsupported provider."
        }
    }
}

private struct OpenAIModelsResponse: Decodable {
    struct Model: Decodable {
        var id: String
    }

    var data: [Model]
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    var model: String
    var messages: [Message]
    var temperature: Double
    var stream: Bool
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String
        }

        var message: Message
    }

    var choices: [Choice]
}

private struct OpenAIEmbedRequest: Encodable {
    var model: String
    var input: [String]
}

private struct OpenAIEmbedResponse: Decodable {
    struct Item: Decodable {
        var index: Int
        var embedding: [Double]
    }

    var data: [Item]
}

private struct AnthropicModelsResponse: Decodable {
    struct Model: Decodable {
        var id: String
        var displayName: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    var data: [Model]
}

private struct AnthropicChatRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    var model: String
    var system: String?
    var messages: [Message]
    var temperature: Double
    var maxTokens: Int

    private enum CodingKeys: String, CodingKey {
        case model
        case system
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicChatResponse: Decodable {
    struct Content: Decodable {
        var type: String
        var text: String?
    }

    var content: [Content]
}

private struct GoogleModelsResponse: Decodable {
    struct Model: Decodable {
        var name: String
        var displayName: String?
    }

    var models: [Model]
}

private struct GoogleGenerateContentRequest: Encodable {
    struct Content: Encodable {
        var role: String?
        var parts: [Part]
    }

    struct Part: Encodable {
        var text: String
    }

    var systemInstruction: Content?
    var contents: [Content]
}

private struct GoogleGenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                var text: String?
            }

            var parts: [Part]
        }

        var content: Content
    }

    var candidates: [Candidate]
}

private struct GoogleEmbedContentRequest: Encodable {
    struct Content: Encodable {
        struct Part: Encodable {
            var text: String
        }

        var parts: [Part]
    }

    var content: Content
}

private struct GoogleEmbedContentResponse: Decodable {
    struct Embedding: Decodable {
        var values: [Double]
    }

    var embedding: Embedding
}
