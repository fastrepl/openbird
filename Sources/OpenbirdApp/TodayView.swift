import SwiftUI
import OpenbirdKit

struct TodayView: View {
    @ObservedObject var model: AppModel
    @State private var isShowingSupportingEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                DatePicker("Day", selection: Binding(
                    get: { model.selectedDay },
                    set: { model.selectDay($0) }
                ), displayedComponents: .date)
                .datePickerStyle(.compact)

                Spacer()

                Button("Inspect Evidence") {
                    model.isShowingRawLogInspector = true
                }
                Button("Generate Summary") {
                    model.generateTodayJournal()
                }
                .buttonStyle(.borderedProminent)
            }

            if let journal = model.todayJournal {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if model.needsOnboarding {
                            SetupChecklistView(model: model)
                        }
                        summaryHeader(journal)
                        summaryCard(journal)

                        if journal.sections.isEmpty == false {
                            DisclosureGroup(isExpanded: $isShowingSupportingEvidence) {
                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(journal.sections) { section in
                                        sectionCard(section)
                                    }
                                }
                                .padding(.top, 12)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Supporting Evidence")
                                        .font(.headline)
                                    Text("Grouped source material used to generate this summary.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(20)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    if model.needsOnboarding {
                        SetupChecklistView(model: model)
                    }

                    ContentUnavailableView(
                        "No daily summary yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Capture some activity, then generate a clean summary from your local logs.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(28)
        .navigationTitle("Today")
    }

    private func summaryHeader(_ journal: DailyJournal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Activity Review")
                .font(.system(size: 30, weight: .semibold))

            HStack(spacing: 10) {
                Label(summaryStatusTitle(for: journal), systemImage: journal.providerID == nil ? "sparkles.slash" : "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(summaryStatusBackground(for: journal), in: Capsule())

                if let providerName = model.providerName(for: journal.providerID) {
                    Text(providerName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(summaryStatusDescription(for: journal))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryCard(_ journal: DailyJournal) -> some View {
        let document = JournalMarkdownParser.parse(journal.markdown)

        return VStack(alignment: .leading, spacing: 0) {
            if document.leadingBlocks.isEmpty, document.sections.isEmpty {
                markdownText(journal.markdown, font: .body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(document.leadingBlocks.enumerated()), id: \.offset) { _, block in
                        markdownBlock(block)
                    }

                    ForEach(Array(document.sections.enumerated()), id: \.element.id) { index, section in
                        if index > 0 {
                            Divider()
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Text(section.title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.primary)

                            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                                markdownBlock(block)
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
    }

    private func summaryStatusTitle(for journal: DailyJournal) -> String {
        journal.providerID == nil ? "Fallback Summary" : "LLM Summary"
    }

    private func summaryStatusDescription(for journal: DailyJournal) -> String {
        if journal.providerID == nil {
            return "This review used the local fallback formatter. Connect a model in Settings to generate a more polished LLM summary from the same evidence."
        }
        return "Generated from your local activity logs. Openbird keeps the supporting evidence available for inspection."
    }

    private func summaryStatusBackground(for journal: DailyJournal) -> Color {
        journal.providerID == nil ? Color.orange.opacity(0.16) : Color.blue.opacity(0.14)
    }

    private func sectionCard(_ section: JournalSection) -> some View {
        let event = representativeEvent(for: section)

        return HStack(alignment: .top, spacing: 12) {
            ActivityAppIcon(
                bundleId: event?.bundleId,
                appName: event?.appName ?? section.heading,
                size: 30
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(section.timeRange) • \(section.heading)")
                    .font(.headline)
                ForEach(section.bullets, id: \.self) { bullet in
                    Text("• \(bullet)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
    }

    private func representativeEvent(for section: JournalSection) -> ActivityEvent? {
        let sourceEventIDs = Set(section.sourceEventIDs)
        return model.rawEvents.first { sourceEventIDs.contains($0.id) }
    }

    @ViewBuilder
    private func markdownBlock(_ block: JournalMarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            markdownText(text, font: .body)
                .fixedSize(horizontal: false, vertical: true)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                            .font(.body.weight(.semibold))
                        markdownText(item, font: .body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .table(let table):
            markdownTable(table)
        }
    }

    private func markdownText(_ text: String, font: Font) -> some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            ) {
                Text(attributed)
            } else {
                Text(text)
            }
        }
        .font(font)
        .foregroundStyle(.primary)
        .textSelection(.enabled)
    }

    private func markdownTable(_ table: JournalMarkdownTable) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow {
                ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                    markdownText(header, font: .subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()
                .gridCellColumns(table.headers.count)

            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        markdownText(cell, font: .body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
    }
}
