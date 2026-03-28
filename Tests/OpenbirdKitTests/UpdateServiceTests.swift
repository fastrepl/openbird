import Foundation
import Testing
@testable import OpenbirdKit

@Suite(.serialized)
struct UpdateServiceTests {
    @Test func detectsNewerSemanticVersions() {
        #expect(UpdateService.isVersion("v0.1.2", newerThan: "0.1.1"))
        #expect(UpdateService.isVersion("0.2.0", newerThan: "0.1.9"))
        #expect(UpdateService.isVersion("0.1.1", newerThan: "0.1.1") == false)
        #expect(UpdateService.isVersion("0.1.0", newerThan: "0.1.1") == false)
    }

    @Test func returnsLatestReleaseWhenGitHubHasNewerVersion() async throws {
        let endpoint = URL(string: "https://example.com/latest")!
        UpdateServiceMockURLProtocol.handler = { request in
            #expect(request.url == endpoint)
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "Openbird")
            let payload = """
            {
              "tag_name": "v0.1.2",
              "html_url": "https://github.com/ComputelessComputer/openbird/releases/tag/v0.1.2",
              "assets": [
                {
                  "name": "openbird-v0.1.2-macos-arm64.dmg",
                  "browser_download_url": "https://github.com/ComputelessComputer/openbird/releases/download/v0.1.2/openbird-v0.1.2-macos-arm64.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let service = UpdateService(
            session: makeUpdateServiceSession(),
            latestReleaseURL: endpoint
        )
        let update = try await service.latestUpdate(currentVersion: "0.1.1")

        #expect(update == AppUpdate(
            version: "0.1.2",
            releaseURL: URL(string: "https://github.com/ComputelessComputer/openbird/releases/tag/v0.1.2")!,
            downloadURL: URL(string: "https://github.com/ComputelessComputer/openbird/releases/download/v0.1.2/openbird-v0.1.2-macos-arm64.dmg")!
        ))
    }

    @Test func ignoresCurrentReleaseVersion() async throws {
        let endpoint = URL(string: "https://example.com/latest")!
        UpdateServiceMockURLProtocol.handler = { _ in
            let payload = """
            {
              "tag_name": "v0.1.2",
              "html_url": "https://github.com/ComputelessComputer/openbird/releases/tag/v0.1.2",
              "assets": [
                {
                  "name": "openbird-v0.1.2-macos-arm64.dmg",
                  "browser_download_url": "https://github.com/ComputelessComputer/openbird/releases/download/v0.1.2/openbird-v0.1.2-macos-arm64.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let service = UpdateService(
            session: makeUpdateServiceSession(),
            latestReleaseURL: endpoint
        )
        let update = try await service.latestUpdate(currentVersion: "0.1.2")

        #expect(update == nil)
    }

    @Test func ignoresReleaseWithoutDiskImageAsset() async throws {
        let endpoint = URL(string: "https://example.com/latest")!
        UpdateServiceMockURLProtocol.handler = { _ in
            let payload = """
            {
              "tag_name": "v0.1.3",
              "html_url": "https://github.com/ComputelessComputer/openbird/releases/tag/v0.1.3",
              "assets": [
                {
                  "name": "openbird-v0.1.3-macos-arm64.sha256",
                  "browser_download_url": "https://github.com/ComputelessComputer/openbird/releases/download/v0.1.3/openbird-v0.1.3-macos-arm64.sha256"
                }
              ]
            }
            """
            let response = HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let service = UpdateService(
            session: makeUpdateServiceSession(),
            latestReleaseURL: endpoint
        )
        let update = try await service.latestUpdate(currentVersion: "0.1.2")

        #expect(update == nil)
    }

    private func makeUpdateServiceSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateServiceMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class UpdateServiceMockURLProtocol: URLProtocol, @unchecked Sendable {
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
