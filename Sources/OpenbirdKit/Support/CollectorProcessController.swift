import Foundation

public final class CollectorProcessController: @unchecked Sendable {
    private var process: Process?

    public init() {}

    public func startIfPossible(databaseURL: URL = OpenbirdPaths.databaseURL) {
        guard process == nil,
              let executableURL = resolveCollectorExecutableURL()
        else {
            return
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--database", databaseURL.path]
        do {
            try process.run()
            self.process = process
        } catch {
            self.process = nil
        }
    }

    public func stop() {
        process?.terminate()
        process = nil
    }

    private func resolveCollectorExecutableURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["OPENBIRD_COLLECTOR_PATH"] {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        let current = URL(fileURLWithPath: CommandLine.arguments[0])
        let sibling = current.deletingLastPathComponent().appendingPathComponent("OpenbirdCollector")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }

        return nil
    }
}
