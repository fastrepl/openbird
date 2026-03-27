import ApplicationServices
import AppKit
import Foundation

public struct AccessibilitySnapshotter {
    private let browserURLResolver = BrowserURLResolver()

    public init() {}

    public func snapshotFrontmostWindow() -> WindowSnapshot? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.isHidden == false,
              let bundleID = application.bundleIdentifier
        else {
            return nil
        }

        let axApplication = AXUIElementCreateApplication(application.processIdentifier)
        guard let focusedWindow = copyElementAttribute(axApplication, attribute: kAXFocusedWindowAttribute) else {
            return minimalSnapshot(for: application, bundleID: bundleID)
        }

        if boolAttribute(kAXMinimizedAttribute, on: focusedWindow) == true {
            return nil
        }

        let windowTitle = stringAttribute(kAXTitleAttribute, on: focusedWindow)
            ?? application.localizedName
            ?? bundleID
        let url = browserURLResolver.currentURL(for: bundleID, windowTitle: windowTitle)
            ?? stringAttribute("AXURL", on: focusedWindow)
        let visibleText = collectVisibleText(from: focusedWindow, depth: 0, remainingNodes: 80, remainingCharacters: 2500)

        return WindowSnapshot(
            bundleId: bundleID,
            appName: application.localizedName ?? bundleID,
            windowTitle: windowTitle,
            url: url,
            visibleText: visibleText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            source: "accessibility"
        )
    }

    private func minimalSnapshot(for application: NSRunningApplication, bundleID: String) -> WindowSnapshot {
        WindowSnapshot(
            bundleId: bundleID,
            appName: application.localizedName ?? bundleID,
            windowTitle: application.localizedName ?? bundleID,
            url: browserURLResolver.currentURL(for: bundleID, windowTitle: application.localizedName ?? bundleID),
            visibleText: "",
            source: "workspace"
        )
    }

    private func collectVisibleText(
        from element: AXUIElement,
        depth: Int,
        remainingNodes: Int,
        remainingCharacters: Int
    ) -> String {
        guard depth < 7, remainingNodes > 0, remainingCharacters > 0 else { return "" }

        let role = stringAttribute(kAXRoleAttribute, on: element) ?? ""
        if role.localizedCaseInsensitiveContains("secure") {
            return ""
        }

        var pieces: [String] = []
        let candidateAttributes = [
            kAXValueAttribute,
            kAXDescriptionAttribute,
            kAXTitleAttribute,
            kAXSelectedTextAttribute,
        ]

        for attribute in candidateAttributes {
            guard let text = stringAttribute(attribute, on: element)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  text.isEmpty == false,
                  text.count < 400
            else { continue }
            pieces.append(text)
        }

        let children = copyChildren(for: element)
        let childBudget = max(1, remainingNodes / max(children.count, 1))
        let charBudget = max(80, remainingCharacters / max(children.count + 1, 1))
        for child in children.prefix(12) {
            let childText = collectVisibleText(
                from: child,
                depth: depth + 1,
                remainingNodes: childBudget,
                remainingCharacters: charBudget
            )
            if childText.isEmpty == false {
                pieces.append(childText)
            }
        }

        let merged = pieces
            .joined(separator: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .removingDuplicates()
            .joined(separator: "\n")

        if merged.count <= remainingCharacters {
            return merged
        }
        return String(merged.prefix(remainingCharacters))
    }

    private func copyElementAttribute(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyChildren(for element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard result == .success,
              let array = value as? [Any]
        else {
            return []
        }
        return array.compactMap { item in
            guard CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(item, to: AXUIElement.self)
        }
    }

    private func stringAttribute(_ attribute: String, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        if let string = value as? String {
            return string
        }
        return nil
    }

    private func boolAttribute(_ attribute: String, on element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? Bool
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
