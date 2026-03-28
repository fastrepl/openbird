import Foundation

public struct AppUpdate: Equatable, Sendable {
    public let version: String
    public let releaseURL: URL
    public let downloadURL: URL

    public init(version: String, releaseURL: URL, downloadURL: URL) {
        self.version = version
        self.releaseURL = releaseURL
        self.downloadURL = downloadURL
    }
}
