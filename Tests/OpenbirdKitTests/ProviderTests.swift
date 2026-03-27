import Foundation
import Testing
@testable import OpenbirdKit

@Suite(.serialized)
struct ProviderTests {
    @Test func openAICompatibleProviderParsesModelList() async throws {
        let config = ProviderConfig(
            name: "LM Studio / Compatible",
            kind: .openAICompatible,
            baseURL: "http://localhost:1234/v1",
            chatModel: "qwen",
            embeddingModel: "nomic"
        )

        OpenAICompatibleMockURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/models")
            let payload = #"{"data":[{"id":"qwen"},{"id":"nomic"}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [OpenAICompatibleMockURLProtocol.self]
            return configuration
        }())

        let provider = HostedProvider(config: config, session: session)
        let models = try await provider.listModels()

        #expect(models.map { $0.id } == ["qwen", "nomic"])
    }

    @Test func anthropicProviderUsesAPIKeyHeader() async throws {
        let config = ProviderConfig(
            name: "Anthropic",
            kind: .anthropic,
            baseURL: "https://api.anthropic.com/v1",
            apiKey: "test-key",
            chatModel: "claude-sonnet"
        )

        OpenAICompatibleMockURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/messages")
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
            #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            let payload = #"{"content":[{"type":"text","text":"hello"}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [OpenAICompatibleMockURLProtocol.self]
            return configuration
        }())

        let provider = HostedProvider(config: config, session: session)
        let response = try await provider.chat(
            request: ProviderChatRequest(
                messages: [
                    ChatTurn(role: .system, content: "system"),
                    ChatTurn(role: .user, content: "hi"),
                ]
            )
        )

        #expect(response.content == "hello")
    }

    @Test func googleProviderUsesGoogleAPIKeyHeader() async throws {
        let config = ProviderConfig(
            name: "Google Gemini",
            kind: .google,
            baseURL: "https://generativelanguage.googleapis.com/v1beta",
            apiKey: "gemini-key",
            chatModel: "gemini-2.5-flash"
        )

        OpenAICompatibleMockURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1beta/models/gemini-2.5-flash:generateContent")
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-key")
            let payload = #"{"candidates":[{"content":{"parts":[{"text":"hello from gemini"}]}}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [OpenAICompatibleMockURLProtocol.self]
            return configuration
        }())

        let provider = HostedProvider(config: config, session: session)
        let response = try await provider.chat(
            request: ProviderChatRequest(messages: [ChatTurn(role: .user, content: "hi")])
        )

        #expect(response.content == "hello from gemini")
    }

    @Test func openRouterAddsOpenbirdHeaders() async throws {
        let config = ProviderConfig(
            name: "OpenRouter",
            kind: .openRouter,
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: "router-key"
        )

        OpenAICompatibleMockURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer router-key")
            #expect(request.value(forHTTPHeaderField: "HTTP-Referer") == "https://openbird.app")
            #expect(request.value(forHTTPHeaderField: "X-Title") == "Openbird")
            let payload = #"{"data":[{"id":"openai/gpt-4.1-mini"}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [OpenAICompatibleMockURLProtocol.self]
            return configuration
        }())

        let provider = HostedProvider(config: config, session: session)
        let models = try await provider.listModels()

        #expect(models.map { $0.id } == ["openai/gpt-4.1-mini"])
    }
}

private final class OpenAICompatibleMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
