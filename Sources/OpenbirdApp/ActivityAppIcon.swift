import AppKit
import SwiftUI

struct ActivityAppIcon: View {
    let bundleId: String?
    var bundlePath: String? = nil
    let appName: String
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let bundleId,
               let icon = ActivityAppIconCache.shared.icon(for: bundleId, bundlePath: bundlePath) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    Text(monogram)
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var cornerRadius: CGFloat {
        size * 0.26
    }

    private var monogram: String {
        guard let scalar = appName.unicodeScalars.first(where: { CharacterSet.alphanumerics.contains($0) }) else {
            return "?"
        }
        return String(scalar).uppercased()
    }
}

@MainActor
private final class ActivityAppIconCache {
    static let shared = ActivityAppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private var missingBundleIDs = Set<String>()

    func icon(for bundleId: String, bundlePath: String?) -> NSImage? {
        let key = bundleId as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if missingBundleIDs.contains(bundleId) {
            return nil
        }

        let resolvedBundlePath: String
        if let bundlePath, bundlePath.isEmpty == false {
            resolvedBundlePath = bundlePath
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            resolvedBundlePath = url.path
        } else {
            missingBundleIDs.insert(bundleId)
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: resolvedBundlePath)
        cache.setObject(icon, forKey: key)
        return icon
    }
}
