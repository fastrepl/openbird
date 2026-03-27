import Foundation

struct SnapshotSanitizer {
    func sanitize(_ snapshot: WindowSnapshot) -> WindowSnapshot {
        var sanitized = snapshot
        let normalizedTitle = normalizedWindowTitle(
            snapshot.windowTitle,
            bundleId: snapshot.bundleId
        )
        let preferredTitle = fallbackTitle(
            currentTitle: normalizedTitle,
            visibleText: snapshot.visibleText,
            appName: snapshot.appName,
            bundleId: snapshot.bundleId
        )

        sanitized.windowTitle = preferredTitle
        sanitized.visibleText = normalizedVisibleText(
            snapshot.visibleText,
            appName: snapshot.appName,
            bundleId: snapshot.bundleId,
            title: preferredTitle
        )
        return sanitized
    }

    private func normalizedWindowTitle(_ title: String, bundleId: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        switch bundleId {
        case "com.tinyspeck.slackmacgap":
            return normalizedSlackTitle(trimmed)
        default:
            return trimmed
        }
    }

    private func fallbackTitle(currentTitle: String, visibleText: String, appName: String, bundleId: String) -> String {
        guard isGenericTitle(currentTitle, appName: appName) else { return currentTitle }

        let lines = filteredLines(
            from: visibleText,
            appName: appName,
            bundleId: bundleId,
            title: currentTitle
        )
        return lines.first ?? currentTitle
    }

    private func normalizedVisibleText(_ visibleText: String, appName: String, bundleId: String, title: String) -> String {
        filteredLines(from: visibleText, appName: appName, bundleId: bundleId, title: title)
            .joined(separator: "\n")
    }

    private func filteredLines(from visibleText: String, appName: String, bundleId: String, title: String) -> [String] {
        visibleText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .filter { isDuplicateLine($0, title: title, appName: appName, bundleId: bundleId) == false }
            .filter { isLowSignalLine($0, bundleId: bundleId) == false }
            .deduplicatedByNormalizedText()
    }

    private func normalizedSlackTitle(_ title: String) -> String {
        guard title.hasSuffix(" - Slack") else { return title }

        let withoutSuffix = String(title.dropLast(" - Slack".count))
        let parts = withoutSuffix.components(separatedBy: " - ")
        if parts.count >= 2, let first = parts.first, first.isEmpty == false {
            return first
        }
        return withoutSuffix
    }

    private func isGenericTitle(_ title: String, appName: String) -> Bool {
        title.isEmpty || title.normalizedComparisonKey == appName.normalizedComparisonKey
    }

    private func isDuplicateLine(_ line: String, title: String, appName: String, bundleId: String) -> Bool {
        let normalized = line.normalizedComparisonKey
        guard normalized.isEmpty == false else { return true }

        let normalizedLineTitle = normalizedWindowTitle(line, bundleId: bundleId).normalizedComparisonKey
        return normalized == title.normalizedComparisonKey
            || normalizedLineTitle == title.normalizedComparisonKey
            || normalized == appName.normalizedComparisonKey
    }

    private func isLowSignalLine(_ line: String, bundleId: String) -> Bool {
        let normalized = line.normalizedComparisonKey
        guard normalized.isEmpty == false else { return true }

        let boilerplate = Set([
            "add page to reading list",
            "downloads window",
            "hide sidebar",
            "page menu",
            "pin window",
            "show sidebar",
            "smart search field",
            "start meeting recording",
            "tab group picker",
            "tauri react typescript",
        ])

        if boilerplate.contains(normalized) {
            return true
        }

        if bundleId == "com.tinyspeck.slackmacgap" && normalized == "slack" {
            return true
        }

        return false
    }
}

private extension Array where Element == String {
    func deduplicatedByNormalizedText() -> [String] {
        var seen = Set<String>()
        return filter { value in
            seen.insert(value.normalizedComparisonKey).inserted
        }
    }
}

private extension String {
    var normalizedComparisonKey: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}
