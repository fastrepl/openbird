import CryptoKit
import Foundation

enum ActivityEventContentHash {
    static let compactLength = 64
    static let oversizedLegacyThreshold = 128

    static func make(
        bundleId: String,
        windowTitle: String,
        url: String?,
        visibleText: String
    ) -> String {
        let payload = [bundleId, windowTitle, url ?? "", visibleText]
            .joined(separator: "|")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func compactIfNeeded(
        _ hash: String,
        bundleId: String,
        windowTitle: String,
        url: String?,
        visibleText: String
    ) -> String {
        guard hash.count > oversizedLegacyThreshold else {
            return hash
        }

        return make(
            bundleId: bundleId,
            windowTitle: windowTitle,
            url: url,
            visibleText: visibleText
        )
    }
}
