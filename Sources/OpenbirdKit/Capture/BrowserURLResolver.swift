import AppKit
import Foundation

public struct BrowserURLResolver {
    public init() {}

    public func currentURL(for bundleID: String, windowTitle: String) -> String? {
        guard isPrivateWindow(title: windowTitle) == false else { return nil }
        switch bundleID {
        case "com.apple.Safari":
            return runAppleScript("""
            tell application "Safari"
                if (count of windows) is 0 then return ""
                return URL of current tab of front window
            end tell
            """)
        case "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac":
            return runAppleScript("""
            tell application id "\(bundleID)"
                if (count of windows) is 0 then return ""
                return URL of active tab of front window
            end tell
            """)
        default:
            return nil
        }
    }

    private func isPrivateWindow(title: String) -> Bool {
        let lowered = title.lowercased()
        return lowered.contains("private") || lowered.contains("incognito")
    }

    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        let value = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == true ? nil : value
    }
}
