import ApplicationServices
import AppKit
import Foundation

public struct PermissionsService {
    public init() {}

    public var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public func requestAccessibilityPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
