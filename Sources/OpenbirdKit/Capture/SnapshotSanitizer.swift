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

    func shouldDiscard(_ snapshot: WindowSnapshot) -> Bool {
        if snapshot.bundleId == "com.apple.loginwindow" || snapshot.appName.normalizedComparisonKey == "loginwindow" {
            return true
        }
        return false
    }

    private func normalizedWindowTitle(_ title: String, bundleId: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        switch bundleId {
        case "com.tinyspeck.slackmacgap":
            return normalizedSlackTitle(trimmed)
        case "com.kakao.KakaoTalkMac":
            return normalizedKakaoTalkTitle(trimmed)
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
        return lines.first.map { strippingSpeakerMarker(from: $0) } ?? currentTitle
    }

    private func normalizedVisibleText(_ visibleText: String, appName: String, bundleId: String, title: String) -> String {
        filteredLines(from: visibleText, appName: appName, bundleId: bundleId, title: title)
            .joined(separator: "\n")
    }

    private func filteredLines(from visibleText: String, appName: String, bundleId: String, title: String) -> [String] {
        visibleText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { normalizedLine($0, bundleId: bundleId) }
            .map { cleanedLine($0, bundleId: bundleId) }
            .filter { $0.isEmpty == false }
            .filter { isDuplicateLine($0, title: title, appName: appName, bundleId: bundleId) == false }
            .filter { isLowSignalLine($0, bundleId: bundleId) == false }
            .deduplicatedByNormalizedText()
    }

    private func cleanedLine(_ line: String, bundleId: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        let speakerMarker = speakerMarker(in: trimmed)
        let content = strippingSpeakerMarker(from: trimmed)
        guard content.isEmpty == false else { return "" }

        if browserBundleIDs.contains(bundleId) {
            if browserChromeFragments.filter({ content.normalizedComparisonKey.contains($0) }).count >= 2 {
                return ""
            }
        }

        if bundleId == "com.kakao.KakaoTalkMac" {
            if kakaoTalkChromeFragments.filter({ content.normalizedComparisonKey.contains($0) }).count >= 2 {
                return ""
            }
        }

        if bundleId == "com.tinyspeck.slackmacgap" {
            if slackChromeFragments.filter({ content.normalizedComparisonKey.contains($0) }).count >= 2 {
                return ""
            }
        }

        guard let speakerMarker else {
            return content
        }

        return speakerMarker + content
    }

    private func normalizedLine(_ line: String, bundleId: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        let speakerMarker = speakerMarker(in: trimmed)
        let content = strippingSpeakerMarker(from: trimmed)
        let normalizedContent = normalizedWindowTitle(content, bundleId: bundleId)
        guard normalizedContent.isEmpty == false else { return "" }

        guard let speakerMarker else {
            return normalizedContent
        }

        return speakerMarker + normalizedContent
    }

    private func normalizedSlackTitle(_ title: String) -> String {
        let normalizedTitle = strippedSlackUnreadMarker(from: title)
        guard normalizedTitle.hasSuffix(" - Slack") else { return normalizedTitle }

        let withoutSuffix = String(normalizedTitle.dropLast(" - Slack".count))
        var parts = withoutSuffix.components(separatedBy: " - ")
        guard parts.count >= 2 else { return withoutSuffix }

        if let last = parts.last, isSlackStatusSegment(last) {
            parts.removeLast()
        }

        guard parts.count >= 2 else {
            return strippedSlackUnreadMarker(from: parts.first ?? withoutSuffix)
        }

        parts.removeLast()
        let normalized = strippedSlackUnreadMarker(
            from: parts.joined(separator: " - ")
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty == false {
            return normalized
        }
        return strippedSlackUnreadMarker(from: withoutSuffix)
    }

    private func isSlackStatusSegment(_ segment: String) -> Bool {
        let normalized = segment.normalizedComparisonKey
        let words = normalized.split(separator: " ")
        guard let first = words.first, Int(first) != nil else { return false }

        return normalized.contains("new item")
            || normalized.contains("new message")
            || normalized.contains("unread")
            || normalized.contains("mention")
            || normalized.contains("reply")
            || normalized.contains("thread")
    }

    private func strippedSlackUnreadMarker(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["* ", "• ", "● ", "◦ "] where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func normalizedKakaoTalkTitle(_ title: String) -> String {
        let normalized = title.normalizedComparisonKey
        if normalized.isEmpty {
            return ""
        }
        if normalized.allSatisfy({ $0.isNumber || $0 == " " }) {
            return ""
        }
        return title
    }

    private func isGenericTitle(_ title: String, appName: String) -> Bool {
        title.isEmpty || title.normalizedComparisonKey == appName.normalizedComparisonKey
    }

    private func isDuplicateLine(_ line: String, title: String, appName: String, bundleId: String) -> Bool {
        let content = strippingSpeakerMarker(from: line)
        let normalized = content.normalizedComparisonKey
        guard normalized.isEmpty == false else { return true }

        let normalizedLineTitle = normalizedWindowTitle(content, bundleId: bundleId).normalizedComparisonKey
        return normalized == title.normalizedComparisonKey
            || normalizedLineTitle == title.normalizedComparisonKey
            || normalized == appName.normalizedComparisonKey
    }

    private func isLowSignalLine(_ line: String, bundleId: String) -> Bool {
        let normalized = strippingSpeakerMarker(from: line).normalizedComparisonKey
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

        if browserBundleIDs.contains(bundleId),
           browserChromeFragments.contains(where: normalized.contains) {
            return true
        }

        if bundleId == "com.apple.MobileSMS" {
            if messageChromeLines.contains(normalized) {
                return true
            }
            if normalized.hasPrefix("search ") {
                return true
            }
        }

        if bundleId == "com.kakao.KakaoTalkMac" {
            if kakaoTalkChromeLines.contains(normalized) {
                return true
            }
            if kakaoTalkChromeFragments.contains(where: normalized.contains) {
                return true
            }
            if normalized.contains("new message") || normalized.contains("new messages") {
                return true
            }
            if normalized.contains("chatrooms") {
                return true
            }
            if normalized.allSatisfy({ $0.isNumber || $0 == " " }) {
                return true
            }
            if isTimeLikeLine(normalized) {
                return true
            }
        }

        if bundleId == "com.tinyspeck.slackmacgap" && normalized == "slack" {
            return true
        }

        if bundleId == "com.tinyspeck.slackmacgap",
           (normalized.hasPrefix("message to ")
            || normalized.hasPrefix("reply to thread in ")
            || normalized.hasPrefix("send a message to ")) {
            return true
        }

        if bundleId == "com.tinyspeck.slackmacgap",
           slackChromeFragments.contains(where: normalized.contains) {
            return true
        }

        return false
    }

    private func speakerMarker(in line: String) -> String? {
        if line.hasPrefix("Me: ") {
            return "Me: "
        }
        if line.hasPrefix("Them: ") {
            return "Them: "
        }
        return nil
    }

    private func strippingSpeakerMarker(from line: String) -> String {
        guard let speakerMarker = speakerMarker(in: line) else {
            return line.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return String(line.dropFirst(speakerMarker.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isTimeLikeLine(_ normalized: String) -> Bool {
        let words = normalized.split(separator: " ")
        guard words.isEmpty == false else { return true }

        let dateTokens = Set(["am", "pm", "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec"])
        return words.allSatisfy { word in
            word.allSatisfy(\.isNumber) || dateTokens.contains(String(word))
        }
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

private let messageChromeLines: Set<String> = [
    "compose",
    "filter",
    "message",
    "messages",
    "search",
    "start facetime",
]

private let browserBundleIDs: Set<String> = [
    "com.apple.Safari",
    "com.google.Chrome",
    "company.thebrowser.Browser",
    "com.brave.Browser",
    "com.microsoft.edgemac",
]

private let browserChromeFragments: [String] = [
    "add page to reading list",
    "downloads",
    "go back",
    "go forward",
    "page menu",
    "pinned tabs",
    "show sidebar",
    "sidebar",
    "tab bar",
    "tab group picker",
    "tabs",
]

private let kakaoTalkChromeLines: Set<String> = [
    "add chatroom",
    "all folder",
    "button",
    "chatlist icon notioff",
    "chatroom folder",
    "chats",
    "common icon newdot",
    "common icon triangledown",
    "emoticon",
    "enter a message",
    "kakaotalk",
    "notifications",
    "profile",
    "search",
    "settings",
    "silent chatroom",
    "unread folder",
]

private let kakaoTalkChromeFragments: [String] = [
    "add chatroom",
    "all folder",
    "chatroom folder",
    "common icon",
    "newdot",
    "notifications",
    "search",
    "settings",
    "silent chatroom",
    "unread folder",
]

private let slackChromeFragments: [String] = [
    "activity",
    "channels",
    "direct messages",
    "huddles",
    "jump to",
    "later",
    "more",
    "threads",
]
