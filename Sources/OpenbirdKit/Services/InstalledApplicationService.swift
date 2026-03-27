import Foundation

public struct InstalledApplicationService: Sendable {
    public init() {}

    public func listInstalledApplications() -> [InstalledApplication] {
        let searchDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]

        var applicationsByBundleID: [String: InstalledApplication] = [:]

        for directory in searchDirectories {
            guard FileManager.default.fileExists(atPath: directory.path) else {
                continue
            }

            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                      let application = installedApplication(at: url),
                      isOpenbird(application) == false else {
                    continue
                }

                applicationsByBundleID[application.bundleID] = application
            }
        }

        return applicationsByBundleID.values.sorted { lhs, rhs in
            let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameComparison == .orderedSame {
                return lhs.bundleID.localizedCaseInsensitiveCompare(rhs.bundleID) == .orderedAscending
            }
            return nameComparison == .orderedAscending
        }
    }

    private func installedApplication(at url: URL) -> InstalledApplication? {
        guard let bundle = Bundle(url: url) else {
            return nil
        }

        let bundleID = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard bundleID.isEmpty == false else {
            return nil
        }

        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        let name = (displayName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { value in
            value.isEmpty ? nil : value
        } ?? (bundleName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { value in
            value.isEmpty ? nil : value
        } ?? url.deletingPathExtension().lastPathComponent

        return InstalledApplication(bundleID: bundleID, name: name)
    }

    private func isOpenbird(_ application: InstalledApplication) -> Bool {
        if let currentBundleID = Bundle.main.bundleIdentifier?.lowercased(),
           currentBundleID == application.bundleID.lowercased() {
            return true
        }

        return application.name.caseInsensitiveCompare("Openbird") == .orderedSame
    }
}
