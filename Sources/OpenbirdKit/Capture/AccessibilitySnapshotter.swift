import ApplicationServices
import AppKit
import Foundation

public struct AccessibilitySnapshotter {
    private let browserURLResolver = BrowserURLResolver()
    private let snapshotSanitizer = SnapshotSanitizer()

    public init() {}

    public func snapshotFrontmostWindow() -> WindowSnapshot? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.isHidden == false,
              let bundleID = application.bundleIdentifier
        else {
            return nil
        }

        let axApplication = AXUIElementCreateApplication(application.processIdentifier)
        guard let focusedWindow = copyElementAttribute(axApplication, attribute: kAXFocusedWindowAttribute)
                ?? copyElementAttribute(axApplication, attribute: kAXMainWindowAttribute)
        else {
            return snapshotSanitizer.sanitize(minimalSnapshot(for: application, bundleID: bundleID))
        }

        if boolAttribute(kAXMinimizedAttribute, on: focusedWindow) == true {
            return nil
        }

        let windowTitle = stringAttribute(kAXTitleAttribute, on: focusedWindow)
            ?? application.localizedName
            ?? bundleID
        let url = browserURLResolver.currentURL(for: bundleID, windowTitle: windowTitle)
            ?? stringAttribute("AXURL", on: focusedWindow)
        let windowText = collectVisibleText(from: focusedWindow, depth: 0, remainingNodes: 220, remainingCharacters: 4000)
        let focusedElementText = copyElementAttribute(axApplication, attribute: kAXFocusedUIElementAttribute)
            .map { collectVisibleText(from: $0, depth: 0, remainingNodes: 60, remainingCharacters: 1200) }
            ?? ""
        let visibleText = mergeTextFragments([windowText, focusedElementText])

        let snapshot = WindowSnapshot(
            bundleId: bundleID,
            appName: application.localizedName ?? bundleID,
            windowTitle: windowTitle,
            url: url,
            visibleText: visibleText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            source: "accessibility"
        )
        return snapshotSanitizer.sanitize(snapshot)
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
        guard depth < 9, remainingNodes > 0, remainingCharacters > 0 else { return "" }

        let role = stringAttribute(kAXRoleAttribute, on: element) ?? ""
        if role.localizedCaseInsensitiveContains("secure") {
            return ""
        }

        var pieces: [String] = []
        if shouldCollectText(for: role) {
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
        }

        let children = prioritizedChildren(for: element)
        let childCount = max(children.count, 1)
        let preferredChildCount = min(12, childCount)
        let childBudget = max(4, remainingNodes / preferredChildCount)
        let charBudget = max(160, remainingCharacters / preferredChildCount)
        for child in children.prefix(min(preferredChildCount, remainingNodes)) {
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

    private func mergeTextFragments(_ fragments: [String]) -> String {
        fragments
            .joined(separator: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .removingDuplicates()
            .joined(separator: "\n")
    }

    private func copyElementAttribute(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func copyChildren(for element: AXUIElement) -> [AXUIElement] {
        let attributes = [kAXVisibleChildrenAttribute, kAXContentsAttribute, kAXChildrenAttribute]
        for attribute in attributes {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            guard result == .success,
                  let array = value as? [Any]
            else {
                continue
            }
            let elements: [AXUIElement] = array.compactMap { item in
                let object = item as AnyObject
                guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
                return unsafeDowncast(object, to: AXUIElement.self)
            }
            if elements.isEmpty == false {
                return elements
            }
        }
        return []
    }

    private func prioritizedChildren(for element: AXUIElement) -> [AXUIElement] {
        copyChildren(for: element).sorted { lhs, rhs in
            let lhsRole = stringAttribute(kAXRoleAttribute, on: lhs) ?? ""
            let rhsRole = stringAttribute(kAXRoleAttribute, on: rhs) ?? ""
            let lhsPriority = childPriority(for: lhsRole)
            let rhsPriority = childPriority(for: rhsRole)
            if lhsPriority != rhsPriority {
                return lhsPriority > rhsPriority
            }

            let lhsArea = elementArea(for: lhs)
            let rhsArea = elementArea(for: rhs)
            if lhsArea != rhsArea {
                return lhsArea > rhsArea
            }

            let lhsX = elementOriginX(for: lhs)
            let rhsX = elementOriginX(for: rhs)
            if lhsX != rhsX {
                return lhsX > rhsX
            }

            return lhsRole < rhsRole
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

    private func shouldCollectText(for role: String) -> Bool {
        blockedRoles.contains(role) == false
    }

    private func childPriority(for role: String) -> Int {
        if primaryContentRoles.contains(role) {
            return 4
        }
        if secondaryContentRoles.contains(role) {
            return 3
        }
        if role == "AXTextField" {
            return 1
        }
        if blockedRoles.contains(role) {
            return 0
        }
        return 2
    }

    private func elementArea(for element: AXUIElement) -> CGFloat {
        guard let size = cgSizeAttribute(kAXSizeAttribute, on: element) else {
            return 0
        }
        return size.width * size.height
    }

    private func elementOriginX(for element: AXUIElement) -> CGFloat {
        cgPointAttribute(kAXPositionAttribute, on: element)?.x ?? 0
    }

    private func cgPointAttribute(_ attribute: String, on element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let pointValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(pointValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(pointValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func cgSizeAttribute(_ attribute: String, on element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let sizeValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(sizeValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return size
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private let blockedRoles: Set<String> = [
    "AXButton",
    "AXCheckBox",
    "AXDisclosureTriangle",
    "AXImage",
    "AXIncrementor",
    "AXMenu",
    "AXMenuBar",
    "AXMenuBarItem",
    "AXMenuButton",
    "AXPopUpButton",
    "AXRadioButton",
    "AXScrollBar",
    "AXTab",
    "AXTabGroup",
    "AXToolbar",
    "AXWindow",
]

private let primaryContentRoles: Set<String> = [
    "AXBrowser",
    "AXCell",
    "AXDocument",
    "AXHeading",
    "AXLayoutArea",
    "AXList",
    "AXListItem",
    "AXOutline",
    "AXRow",
    "AXScrollArea",
    "AXStaticText",
    "AXTable",
    "AXTextArea",
    "AXWebArea",
]

private let secondaryContentRoles: Set<String> = [
    "AXGroup",
    "AXSplitGroup",
]
