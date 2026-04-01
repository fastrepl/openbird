import Foundation

public struct JournalMarkdownDocument: Hashable, Sendable {
    public var leadingBlocks: [JournalMarkdownBlock]
    public var sections: [JournalMarkdownSection]

    public init(
        leadingBlocks: [JournalMarkdownBlock] = [],
        sections: [JournalMarkdownSection] = []
    ) {
        self.leadingBlocks = leadingBlocks
        self.sections = sections
    }
}

public struct JournalMarkdownSection: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var blocks: [JournalMarkdownBlock]

    public init(
        id: String = UUID().uuidString,
        title: String,
        blocks: [JournalMarkdownBlock]
    ) {
        self.id = id
        self.title = title
        self.blocks = blocks
    }
}

public struct JournalMarkdownTable: Hashable, Sendable {
    public var headers: [String]
    public var rows: [[String]]

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }
}

public enum JournalMarkdownBlock: Hashable, Sendable {
    case paragraph(String)
    case bulletList([String])
    case orderedList([String])
    case table(JournalMarkdownTable)
}

public enum JournalMarkdownParser {
    public static func parse(_ markdown: String) -> JournalMarkdownDocument {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)

        var leadingBlocks: [JournalMarkdownBlock] = []
        var sections: [JournalMarkdownSection] = []
        var currentSectionTitle: String?
        var currentBlocks: [JournalMarkdownBlock] = []
        var index = 0

        func appendBlock(_ block: JournalMarkdownBlock) {
            if currentSectionTitle == nil {
                leadingBlocks.append(block)
            } else {
                currentBlocks.append(block)
            }
        }

        func flushSection() {
            guard let currentSectionTitle else { return }
            sections.append(
                JournalMarkdownSection(
                    title: currentSectionTitle,
                    blocks: currentBlocks
                )
            )
            currentBlocks = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if shouldIgnoreDocumentTitle(
                trimmed,
                hasLeadingBlocks: leadingBlocks.isEmpty == false,
                hasSections: sections.isEmpty == false,
                hasCurrentSection: currentSectionTitle != nil
            ) {
                index += 1
                continue
            }

            if let heading = sectionHeading(from: trimmed) {
                flushSection()
                currentSectionTitle = heading
                index += 1
                continue
            }

            if let (table, nextIndex) = parseTable(lines: lines, startIndex: index) {
                appendBlock(.table(table))
                index = nextIndex
                continue
            }

            if let (items, nextIndex) = parseBulletList(lines: lines, startIndex: index) {
                appendBlock(.bulletList(items))
                index = nextIndex
                continue
            }

            if let (items, nextIndex) = parseOrderedList(lines: lines, startIndex: index) {
                appendBlock(.orderedList(items))
                index = nextIndex
                continue
            }

            let (paragraph, nextIndex) = parseParagraph(lines: lines, startIndex: index)
            appendBlock(.paragraph(paragraph))
            index = nextIndex
        }

        flushSection()

        return JournalMarkdownDocument(
            leadingBlocks: leadingBlocks,
            sections: sections
        )
    }

    private static func shouldIgnoreDocumentTitle(
        _ line: String,
        hasLeadingBlocks: Bool,
        hasSections: Bool,
        hasCurrentSection: Bool
    ) -> Bool {
        guard hasLeadingBlocks == false,
              hasSections == false,
              hasCurrentSection == false
        else {
            return false
        }

        return line.hasPrefix("# ") || line.hasPrefix("Title:")
    }

    private static func sectionHeading(from line: String) -> String? {
        let supportedPrefixes = ["## ", "### "]
        guard let prefix = supportedPrefixes.first(where: { line.hasPrefix($0) }) else {
            return nil
        }

        let title = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func parseBulletList(
        lines: [String],
        startIndex: Int
    ) -> ([String], Int)? {
        guard bulletText(from: lines[startIndex]) != nil else {
            return nil
        }

        var items: [String] = []
        var index = startIndex

        while index < lines.count {
            if let bullet = bulletText(from: lines[index]) {
                items.append(bullet)
                index += 1
                continue
            }

            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
            }
            break
        }

        return (items, index)
    }

    private static func bulletText(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefixes = ["- ", "* "]

        guard let prefix = prefixes.first(where: { trimmed.hasPrefix($0) }) else {
            return nil
        }

        let text = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func parseTable(
        lines: [String],
        startIndex: Int
    ) -> (JournalMarkdownTable, Int)? {
        guard startIndex + 1 < lines.count else { return nil }

        let headerLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[startIndex + 1].trimmingCharacters(in: .whitespaces)

        let headers = tableCells(from: headerLine)
        guard headers.count >= 2, isTableSeparator(separatorLine, columnCount: headers.count) else {
            return nil
        }

        var rows: [[String]] = []
        var index = startIndex + 2

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.isEmpty == false else {
                index += 1
                break
            }

            let cells = tableCells(from: trimmed)
            guard cells.count == headers.count else {
                break
            }

            rows.append(cells)
            index += 1
        }

        return (JournalMarkdownTable(headers: headers, rows: rows), index)
    }

    private static func tableCells(from line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }

        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ line: String, columnCount: Int) -> Bool {
        let columns = tableCells(from: line)
        guard columns.count == columnCount else { return false }

        return columns.allSatisfy { column in
            let stripped = column.replacingOccurrences(of: ":", with: "")
            return stripped.isEmpty == false && stripped.allSatisfy { $0 == "-" }
        }
    }

    private static func parseOrderedList(
        lines: [String],
        startIndex: Int
    ) -> ([String], Int)? {
        guard orderedListText(from: lines[startIndex]) != nil else {
            return nil
        }

        var items: [String] = []
        var index = startIndex

        while index < lines.count {
            if let item = orderedListText(from: lines[index]) {
                items.append(item)
                index += 1
                continue
            }

            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
            }
            break
        }

        return (items, index)
    }

    private static func orderedListText(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let firstSpaceIndex = trimmed.firstIndex(of: " ") else {
            return nil
        }

        let marker = trimmed[..<firstSpaceIndex]
        guard marker.hasSuffix(".") else {
            return nil
        }

        let numberPortion = marker.dropLast()
        guard numberPortion.isEmpty == false && numberPortion.allSatisfy(\.isNumber) else {
            return nil
        }

        let text = trimmed[firstSpaceIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func parseParagraph(
        lines: [String],
        startIndex: Int
    ) -> (String, Int) {
        var collected: [String] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty ||
                sectionHeading(from: trimmed) != nil ||
                bulletText(from: line) != nil ||
                orderedListText(from: line) != nil {
                break
            }

            if parseTable(lines: lines, startIndex: index) != nil {
                break
            }

            collected.append(trimmed)
            index += 1
        }

        return (collected.joined(separator: " "), index)
    }
}
