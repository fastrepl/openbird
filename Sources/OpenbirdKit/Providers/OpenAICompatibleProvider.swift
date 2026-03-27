import Foundation

public struct OpenAICompatibleProvider: LLMProvider {
    public let config: ProviderConfig
    private let session: URLSession

    public init(config: ProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func listModels() async throws -> [ProviderModelInfo] {
        let response: OpenAIModelsResponse = try await performRequest(path: "/models")
        return response.data.map { ProviderModelInfo(id: $0.id) }
    }

    public func chat(request: ProviderChatRequest) async throws -> ProviderChatResponse {
        let payload = OpenAIChatRequest(
            model: config.chatModel,
            messages: request.messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            temperature: request.temperature,
            stream: request.stream
        )
        let response: OpenAIChatResponse = try await performRequest(path: "/chat/completions", method: "POST", body: payload)
        return ProviderChatResponse(content: response.choices.first?.message.content ?? "")
    }

    public func embed(texts: [String]) async throws -> [[Double]] {
        guard config.embeddingModel.isEmpty == false else { return [] }
        let payload = OpenAIEmbedRequest(model: config.embeddingModel, input: texts)
        let response: OpenAIEmbedResponse = try await performRequest(path: "/embeddings", method: "POST", body: payload)
        return response.data.sorted(by: { $0.index < $1.index }).map(\.embedding)
    }

    public func healthCheck() async throws -> Bool {
        let _: OpenAIModelsResponse = try await performRequest(path: "/models")
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
        if config.apiKey.isEmpty == false {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in config.customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
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
            throw NSError(domain: "OpenAICompatibleProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
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
