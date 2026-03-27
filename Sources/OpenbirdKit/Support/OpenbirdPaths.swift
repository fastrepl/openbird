import Foundation

public enum OpenbirdPaths {
    public static let applicationSupportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("Openbird", isDirectory: true)
    }()

    public static let databaseURL = applicationSupportDirectory.appendingPathComponent("openbird.sqlite")

    public static func ensureApplicationSupportDirectory() throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
    }
}
