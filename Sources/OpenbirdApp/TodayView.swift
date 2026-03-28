import SwiftUI
import OpenbirdKit

struct TodayView: View {
    @ObservedObject var model: AppModel
    @State private var isShowingSupportingEvidence = false
    @State private var supportingEvidenceItems: [SupportingEvidenceItem] = []
    @State private var isPreparingSupportingEvidence = false

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
                                Group {
                                    if isPreparingSupportingEvidence && supportingEvidenceItems.isEmpty {
                                        ProgressView("Loading evidence…")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        VStack(alignment: .leading, spacing: 14) {
                                            ForEach(supportingEvidenceItems) { item in
                                                sectionCard(item)
                                            }
                                        }
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
        .task(id: supportingEvidencePreparationKey) {
            await prepareSupportingEvidence()
        }
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

    private func sectionCard(_ item: SupportingEvidenceItem) -> some View {
        return HStack(alignment: .top, spacing: 12) {
            ActivityAppIcon(
                bundleId: item.bundleId,
                bundlePath: item.bundlePath,
                appName: item.appName,
                size: 30
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(item.timeRange) • \(item.heading)")
                    .font(.headline)
                ForEach(item.bullets, id: \.self) { bullet in
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

    private var supportingEvidencePreparationKey: SupportingEvidencePreparationKey {
        SupportingEvidencePreparationKey(
            journalID: model.todayJournal?.id,
            rawEventCount: model.rawEvents.count,
            rawEventLastID: model.rawEvents.last?.id,
            installedApplicationCount: model.installedApplications.count
        )
    }

    @MainActor
    private func prepareSupportingEvidence() async {
        guard let journal = model.todayJournal else {
            supportingEvidenceItems = []
            isPreparingSupportingEvidence = false
            return
        }

        let sections = journal.sections
        let rawEvents = model.rawEvents
        let installedApplications = model.installedApplications

        isPreparingSupportingEvidence = true

        let items = await Task.detached(priority: .userInitiated) {
            let eventsByID = Dictionary(uniqueKeysWithValues: rawEvents.map { ($0.id, $0) })
            let applicationsByBundleID = Dictionary(uniqueKeysWithValues: installedApplications.map {
                ($0.bundleID.lowercased(), $0)
            })

            return sections.map { section in
                let representativeEvent = section.sourceEventIDs.lazy.compactMap { eventsByID[$0] }.first
                let bundlePath = representativeEvent.flatMap { event in
                    applicationsByBundleID[event.bundleId.lowercased()]?.bundlePath
                }

                return SupportingEvidenceItem(
                    id: section.id,
                    heading: section.heading,
                    timeRange: section.timeRange,
                    bullets: section.bullets,
                    bundleId: representativeEvent?.bundleId,
                    bundlePath: bundlePath,
                    appName: representativeEvent?.appName ?? section.heading
                )
            }
        }.value

        guard Task.isCancelled == false else {
            return
        }

        supportingEvidenceItems = items
        isPreparingSupportingEvidence = false
    }
}

private struct SupportingEvidenceItem: Identifiable, Sendable {
    let id: String
    let heading: String
    let timeRange: String
    let bullets: [String]
    let bundleId: String?
    let bundlePath: String?
    let appName: String
}

private struct SupportingEvidencePreparationKey: Equatable {
    let journalID: String?
    let rawEventCount: Int
    let rawEventLastID: String?
    let installedApplicationCount: Int
}
