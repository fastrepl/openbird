import Foundation
import Testing
@testable import OpenbirdKit

struct OllamaProviderTests {
    @Test func stripsV1AndSetsOriginHeader() async throws {
        let config = ProviderConfig(
            name: "Ollama",
            kind: .ollama,
            baseURL: "http://127.0.0.1:11434/v1",
            chatModel: "llama3.2",
            embeddingModel: "nomic-embed-text"
        )

        OllamaMockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "http://127.0.0.1:11434/api/tags")
            #expect(request.value(forHTTPHeaderField: "Origin") == "http://127.0.0.1:11434")
            let payload = #"{"models":[{"name":"llama3.2"},{"name":"nomic-embed-text"}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [OllamaMockURLProtocol.self]
            return configuration
        }())

        let provider = OllamaProvider(config: config, session: session)
        let models = try await provider.listModels()

        #expect(models.map { $0.id } == ["llama3.2", "nomic-embed-text"])
    }
}

private final class OllamaMockURLProtocol: URLProtocol, @unchecked Sendable {
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
