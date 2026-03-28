import AppKit
import Foundation
import OpenbirdKit

actor AppUpdater {
    private let session: URLSession
    private let fileManager: FileManager

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.session = session
        self.fileManager = fileManager
    }

    func install(update: AppUpdate, appBundleURL: URL) async throws {
        guard appBundleURL.pathExtension == "app" else {
            throw AppUpdaterError.unavailableForDevelopmentBuilds
        }

        let (downloadedFileURL, _) = try await session.download(from: update.downloadURL)
        let diskImageURL = try moveDownloadToTemporaryDiskImage(downloadedFileURL)

        let mountPointURL = try attachDiskImage(at: diskImageURL)
        let sourceAppURL = try applicationBundle(in: mountPointURL)
        let destinationAppURL = preferredInstallationURL(for: appBundleURL)
        let requiresAdministratorPrivileges = installationRequiresAdministratorPrivileges(
            destinationAppURL: destinationAppURL
        )

        try launchInstaller(
            processID: ProcessInfo.processInfo.processIdentifier,
            sourceAppURL: sourceAppURL,
            destinationAppURL: destinationAppURL,
            mountPointURL: mountPointURL,
            diskImageURL: diskImageURL,
            requiresAdministratorPrivileges: requiresAdministratorPrivileges
        )
    }

    private func moveDownloadToTemporaryDiskImage(_ downloadedFileURL: URL) throws -> URL {
        let destinationURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("dmg")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: downloadedFileURL, to: destinationURL)
        return destinationURL
    }

    private func attachDiskImage(at diskImageURL: URL) throws -> URL {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", "-plist", "-nobrowse", "-readonly", diskImageURL.path]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw AppUpdaterError.diskImageMountFailed
        }

        let propertyList = try PropertyListSerialization.propertyList(
            from: outputData,
            options: [],
            format: nil
        )
        guard
            let root = propertyList as? [String: Any],
            let entities = root["system-entities"] as? [[String: Any]],
            let mountPoint = entities
                .compactMap({ $0["mount-point"] as? String })
                .first
        else {
            throw AppUpdaterError.diskImageMountFailed
        }

        return URL(fileURLWithPath: mountPoint, isDirectory: true)
    }

    private func applicationBundle(in mountedVolumeURL: URL) throws -> URL {
        let appURL = mountedVolumeURL.appendingPathComponent("Openbird.app", isDirectory: true)
        if fileManager.fileExists(atPath: appURL.path) {
            return appURL
        }

        let contents = try fileManager.contentsOfDirectory(
            at: mountedVolumeURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        guard let discoveredAppURL = contents.first(where: { $0.pathExtension == "app" }) else {
            throw AppUpdaterError.updatedApplicationMissing
        }

        return discoveredAppURL
    }

    private func preferredInstallationURL(for runningAppURL: URL) -> URL {
        let currentDirectoryURL = runningAppURL.deletingLastPathComponent()
        if fileManager.isWritableFile(atPath: currentDirectoryURL.path) {
            return runningAppURL
        }

        return URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent(runningAppURL.lastPathComponent, isDirectory: true)
    }

    private func installationRequiresAdministratorPrivileges(destinationAppURL: URL) -> Bool {
        let destinationDirectoryURL = destinationAppURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: destinationDirectoryURL.path) else {
            return true
        }

        if fileManager.fileExists(atPath: destinationAppURL.path) {
            return fileManager.isWritableFile(atPath: destinationAppURL.path) == false
        }

        return false
    }

    private func launchInstaller(
        processID: Int32,
        sourceAppURL: URL,
        destinationAppURL: URL,
        mountPointURL: URL,
        diskImageURL: URL,
        requiresAdministratorPrivileges: Bool
    ) throws {
        let helperScriptURL = fileManager.temporaryDirectory
            .appendingPathComponent("openbird-update-\(UUID().uuidString)")
            .appendingPathExtension("sh")
        let installCommand = "/bin/rm -rf \(shellQuoted(destinationAppURL.path)) && /usr/bin/ditto \(shellQuoted(sourceAppURL.path)) \(shellQuoted(destinationAppURL.path))"
        let appleScriptInstallCommand = "do shell script \(appleScriptQuoted(installCommand)) with administrator privileges"

        let script = """
        #!/bin/zsh
        set -euo pipefail

        PID=\(processID)
        MOUNT_POINT=\(shellQuoted(mountPointURL.path))
        DISK_IMAGE=\(shellQuoted(diskImageURL.path))
        RELAUNCH_APP=\(shellQuoted(destinationAppURL.path))
        REQUIRES_ADMIN=\(requiresAdministratorPrivileges ? "1" : "0")

        cleanup() {
          /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
          /bin/rm -f "$DISK_IMAGE" "$0"
        }

        trap cleanup EXIT

        while kill -0 "$PID" >/dev/null 2>&1; do
          sleep 1
        done

        if [[ "$REQUIRES_ADMIN" == "1" ]]; then
          /usr/bin/osascript <<'APPLESCRIPT'
        \(appleScriptInstallCommand)
        APPLESCRIPT
        else
          \(installCommand)
        fi

        /usr/bin/open "$RELAUNCH_APP"
        """

        try script.write(to: helperScriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperScriptURL.path)

        let launchProcess = Process()
        launchProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        launchProcess.arguments = [
            "-lc",
            "nohup \(shellQuoted(helperScriptURL.path)) >/dev/null 2>&1 &"
        ]
        try launchProcess.run()
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func appleScriptQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private enum AppUpdaterError: LocalizedError {
    case unavailableForDevelopmentBuilds
    case diskImageMountFailed
    case updatedApplicationMissing

    var errorDescription: String? {
        switch self {
        case .unavailableForDevelopmentBuilds:
            return "Automatic updates are only available in packaged Openbird releases."
        case .diskImageMountFailed:
            return "Openbird could not mount the downloaded update."
        case .updatedApplicationMissing:
            return "The downloaded update did not contain Openbird.app."
        }
    }
}
