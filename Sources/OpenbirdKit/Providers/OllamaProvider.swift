import Foundation

public struct OllamaProvider: LLMProvider {
    public let config: ProviderConfig
    private let session: URLSession

    public init(config: ProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func listModels() async throws -> [ProviderModelInfo] {
        let response: OllamaTagsResponse = try await performRequest(path: "/api/tags")
        return response.models.map { ProviderModelInfo(id: $0.name) }
    }

    public func chat(request: ProviderChatRequest) async throws -> ProviderChatResponse {
        let payload = OllamaChatRequest(
            model: config.chatModel,
            messages: request.messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            stream: request.stream
        )
        let response: OllamaChatResponse = try await performRequest(path: "/api/chat", method: "POST", body: payload)
        return ProviderChatResponse(content: response.message.content)
    }

    public func embed(texts: [String]) async throws -> [[Double]] {
        guard config.embeddingModel.isEmpty == false else { return [] }
        let payload = OllamaEmbedRequest(model: config.embeddingModel, input: texts)
        let response: OllamaEmbedResponse = try await performRequest(path: "/api/embed", method: "POST", body: payload)
        return response.embeddings
    }

    public func healthCheck() async throws -> Bool {
        let _: OllamaTagsResponse = try await performRequest(path: "/api/tags")
        return true
    }

    private func performRequest<Response: Decodable>(
        path: String,
        method: String = "GET",
        bodyData: Data? = nil
    ) async throws -> Response {
        guard let baseURL = URL(string: config.baseURL) else {
            throw URLError(.badURL)
        }
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bodyData {
            request.httpBody = bodyData
        }
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

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed"
            throw NSError(domain: "OllamaProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}

private struct OllamaTagsResponse: Decodable {
    var models: [OllamaModel]
}

private struct OllamaModel: Decodable {
    var name: String
}

private struct OllamaChatRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    var model: String
    var messages: [Message]
    var stream: Bool
}

private struct OllamaChatResponse: Decodable {
    struct Message: Decodable {
        var content: String
    }

    var message: Message
}

private struct OllamaEmbedRequest: Encodable {
    var model: String
    var input: [String]
}

private struct OllamaEmbedResponse: Decodable {
    var embeddings: [[Double]]
}
