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
            Text("Daily Summary")
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
        VStack(alignment: .leading, spacing: 0) {
            if journal.sections.isEmpty {
                Text(journal.markdown)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(journal.sections.enumerated()), id: \.element.id) { index, section in
                        timelineRow(
                            section,
                            event: representativeEvent(for: section),
                            showsConnector: index < journal.sections.count - 1
                        )
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
    
    private func timelineRow(_ section: JournalSection, event: ActivityEvent?, showsConnector: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)

                if showsConnector {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 6)
                }
            }
            .frame(width: 10)

            VStack(alignment: .leading, spacing: 8) {
                Text(section.timeRange)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(section.heading)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                if let appName = event?.appName, appName.normalizedComparisonKey != section.heading.normalizedComparisonKey {
                    Text(appName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(summaryHighlights(for: section, event: event), id: \.self) { highlight in
                    Text(highlight)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, showsConnector ? 10 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryHighlights(for section: JournalSection, event: ActivityEvent?) -> [String] {
        let excluded = Set(
            [section.heading, event?.appName]
                .compactMap { $0?.normalizedComparisonKey }
        )
        var pieces: [String] = []

        for bullet in section.bullets {
            let segments = bullet.split(separator: "•")
            for segment in segments {
                let piece = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard piece.isEmpty == false else { continue }
                guard excluded.contains(piece.normalizedComparisonKey) == false else { continue }
                guard piece.hasPrefix("http") == false else { continue }
                pieces.append(piece)
            }
        }

        return Array(pieces.deduplicatedByNormalizedText().prefix(2))
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
