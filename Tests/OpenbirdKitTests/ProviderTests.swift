import Foundation
import Testing
@testable import OpenbirdKit

struct ProviderTests {
    @Test func openAICompatibleProviderParsesModelList() async throws {
        let config = ProviderConfig(
            name: "LM Studio",
            kind: .openAICompatible,
            baseURL: "http://localhost:1234/v1",
            chatModel: "qwen",
            embeddingModel: "nomic"
        )

        MockURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/models")
            let payload = #"{"data":[{"id":"qwen"},{"id":"nomic"}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MockURLProtocol.self]
            return configuration
        }())

        let provider = OpenAICompatibleProvider(config: config, session: session)
        let models = try await provider.listModels()

        #expect(models.map(\.id) == ["qwen", "nomic"])
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
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
