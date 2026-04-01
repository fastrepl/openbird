import OpenbirdKit
import SwiftUI

struct MarkdownBlocksView: View {
    let blocks: [JournalMarkdownBlock]
    let paragraphFont: Font
    let paragraphColor: Color
    let listFont: Font
    let listColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(
                    block: block,
                    paragraphFont: paragraphFont,
                    paragraphColor: paragraphColor,
                    listFont: listFont,
                    listColor: listColor
                )
            }
        }
    }
}

private struct MarkdownBlockView: View {
    let block: JournalMarkdownBlock
    let paragraphFont: Font
    let paragraphColor: Color
    let listFont: Font
    let listColor: Color

    var body: some View {
        switch block {
        case .paragraph(let text):
            MarkdownTextView(
                markdown: text,
                font: paragraphFont,
                color: paragraphColor
            )
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    listRow(marker: "•", text: item)
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    listRow(marker: "\(index + 1).", text: item)
                }
            }
        case .table(let table):
            MarkdownTableView(table: table)
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker)
                .font(listFont)
                .foregroundStyle(listColor)

            MarkdownTextView(
                markdown: text,
                font: listFont,
                color: listColor
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MarkdownTextView: View {
    let markdown: String
    let font: Font
    let color: Color

    var body: some View {
        Text(renderedText)
            .font(font)
            .foregroundStyle(color)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var renderedText: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )

        if let attributed = try? AttributedString(markdown: markdown, options: options) {
            return attributed
        }

        return AttributedString(markdown)
    }
}

struct MarkdownTableView: View {
    let table: JournalMarkdownTable

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(table.headers, isHeader: true)

            ForEach(Array(table.rows.enumerated()), id: \.offset) { index, values in
                Divider()
                row(values, isHeader: false)
                    .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.03))
            }
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45))
        }
    }

    private func row(_ values: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                MarkdownTextView(
                    markdown: value,
                    font: isHeader ? .subheadline.weight(.semibold) : .subheadline,
                    color: isHeader ? .primary : .secondary
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isHeader ? Color.primary.opacity(0.04) : Color.clear)
    }
}
