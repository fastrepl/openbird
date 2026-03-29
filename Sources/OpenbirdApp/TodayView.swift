import SwiftUI
import OpenbirdKit

struct TodayView: View {
    @ObservedObject var model: AppModel
    @State private var timelineContent: TimelineContent = .empty
    @State private var isPreparingTimeline = false
    @State private var timelinePreparationStatus: TimelinePreparationStatus?
    @State private var isChatExpanded = false
    @FocusState private var focusedField: TodayChatDock.FocusField?
    private let collapsedChatClearance: CGFloat = 92
    private let expandedChatClearance: CGFloat = 420
    private static let selectedDayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMMM"
        return formatter
    }()
    private static let selectedDayYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.needsOnboarding {
                        SetupChecklistView(model: model)
                    }

                    if let loadingStatus = activeLoadingStatus, timelineContent.isEmpty {
                        LoadingStatusCard(status: loadingStatus)
                            .frame(maxWidth: .infinity, minHeight: 280)
                    } else if timelineContent.isEmpty {
                        ContentUnavailableView(
                            "No activity yet",
                            systemImage: "clock.badge.questionmark",
                            description: Text("Openbird will show a timeline of your day here once it captures some activity.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        timelineView
                    }
                }
                .padding(.bottom, chatClearance)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isChatExpanded {
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        collapseChat()
                    }
            }
        }
        .overlay(alignment: .bottom) {
            TodayChatDock(
                model: model,
                isExpanded: $isChatExpanded,
                focusedField: $focusedField
            )
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .onAppear {
            handleChatFocusRequestIfNeeded()
        }
        .onChange(of: model.shouldFocusChatComposer) { _, _ in
            handleChatFocusRequestIfNeeded()
        }
        .onExitCommand {
            collapseChat()
        }
        .task(id: timelinePreparationKey) {
            await prepareTimeline()
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 12) {
                Text(selectedDayTitle)
                    .font(.title3.bold())

                ControlGroup {
                    Button {
                        stepSelectedDay(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .help("Previous day")

                    Button {
                        stepSelectedDay(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .help("Next day")
                    .disabled(isShowingToday)
                }
                .fixedSize()
            }

            Spacer()

            Button {
                model.generateTodayJournal()
            } label: {
                HStack(spacing: 8) {
                    if model.isGeneratingTodayJournal {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(model.isGeneratingTodayJournal ? "Refreshing…" : "Refresh")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isGeneratingTodayJournal)
        }
    }

    @ViewBuilder
    private var timelineView: some View {
        switch timelineContent {
        case .empty:
            EmptyView()
        case .journal(let document, let refreshedAt, let recentItems):
            journalTimeline(document: document, refreshedAt: refreshedAt, recentItems: recentItems)
        case .raw(let items):
            timelineCard(items: items)
        }
    }

    private func journalTimeline(
        document: JournalMarkdownDocument,
        refreshedAt: Date,
        recentItems: [TimelineItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                if document.leadingBlocks.isEmpty == false {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(document.leadingBlocks.enumerated()), id: \.offset) { _, block in
                            JournalMarkdownBlockView(block: block)
                        }
                    }
                    .padding(24)

                    if document.sections.isEmpty == false {
                        Divider()
                    }
                }

                ForEach(Array(document.sections.enumerated()), id: \.element.id) { index, section in
                    if index > 0 {
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text(section.title)
                            .font(.headline)

                        ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                            JournalMarkdownBlockView(block: block)
                        }
                    }
                    .padding(24)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 24))

            if recentItems.isEmpty == false {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Activity")
                        .font(.headline)
                    Text("Summary last refreshed at \(OpenbirdDateFormatting.timeString(for: refreshedAt)). Newer captured activity is shown below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    timelineCard(items: recentItems)
                }
            }
        }
    }

    private func timelineCard(items: [TimelineItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                }
                timelineRow(item)
                    .padding(24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
    }

    private func timelineRow(_ item: TimelineItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ActivityAppIcon(
                bundleId: item.bundleId,
                bundlePath: item.bundlePath,
                appName: item.appName,
                size: 30
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(item.timeRange) — \(item.title)")
                    .font(.headline)

                ForEach(item.bullets, id: \.self) { bullet in
                    Text("• \(bullet)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timelinePreparationKey: TimelinePreparationKey {
        TimelinePreparationKey(
            journalID: model.todayJournal?.id,
            rawEventCount: model.rawEvents.count,
            rawEventLastID: model.rawEvents.last?.id,
            installedApplicationCount: model.installedApplications.count
        )
    }

    private var activeLoadingStatus: LoadingDisplayStatus? {
        if let modelStatus = model.dayLoadStatus {
            return LoadingDisplayStatus(
                step: modelStatus.step,
                totalSteps: modelStatus.totalSteps,
                title: modelStatus.title,
                detail: modelStatus.detail
            )
        }

        guard isPreparingTimeline, let timelinePreparationStatus else {
            return nil
        }

        return timelinePreparationStatus.displayStatus
    }

    private func handleChatFocusRequestIfNeeded() {
        guard model.shouldFocusChatComposer else {
            return
        }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            isChatExpanded = true
        }
        focusedField = .composer
        model.acknowledgeChatFocusRequest()
    }

    private func collapseChat() {
        guard isChatExpanded else {
            return
        }
        focusedField = nil
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            isChatExpanded = false
        }
    }

    private var chatClearance: CGFloat {
        isChatExpanded ? expandedChatClearance : collapsedChatClearance
    }

    private var selectedDayTitle: String {
        let day = Calendar.current.component(.day, from: model.selectedDay)
        let month = Self.selectedDayMonthFormatter.string(from: model.selectedDay)
        let year = Self.selectedDayYearFormatter.string(from: model.selectedDay)
        return "\(month) \(day)\(ordinalSuffix(for: day)), \(year)"
    }

    private var isShowingToday: Bool {
        Calendar.current.isDate(model.selectedDay, inSameDayAs: Date())
    }

    private func stepSelectedDay(by offset: Int) {
        let calendar = Calendar.current
        let currentDay = calendar.startOfDay(for: model.selectedDay)
        let today = calendar.startOfDay(for: Date())

        guard let targetDay = calendar.date(byAdding: .day, value: offset, to: currentDay) else {
            return
        }
        guard targetDay <= today else {
            return
        }

        model.selectDay(targetDay)
    }

    private func ordinalSuffix(for day: Int) -> String {
        let lastTwoDigits = day % 100
        if (11...13).contains(lastTwoDigits) {
            return "th"
        }

        switch day % 10 {
        case 1:
            return "st"
        case 2:
            return "nd"
        case 3:
            return "rd"
        default:
            return "th"
        }
    }

    @MainActor
    private func prepareTimeline() async {
        let journal = model.todayJournal
        let rawEvents = model.rawEvents
        let installedApplications = model.installedApplications

        isPreparingTimeline = true
        timelinePreparationStatus = .groupingActivity
        defer {
            isPreparingTimeline = false
            timelinePreparationStatus = nil
        }

        let rawItems = await Task.detached(priority: .userInitiated) {
            Self.buildTimelineItems(
                rawEvents: rawEvents,
                installedApplications: installedApplications
            )
        }.value

        guard Task.isCancelled == false else {
            return
        }

        guard let journal else {
            timelineContent = rawItems.isEmpty ? .empty : .raw(rawItems)
            return
        }

        timelinePreparationStatus = .parsingJournal
        let parsedJournal = await Task.detached(priority: .userInitiated) {
            Self.parseJournalContent(
                journal: journal,
                rawEvents: rawEvents,
                rawItems: rawItems
            )
        }.value

        guard Task.isCancelled == false else {
            return
        }

        guard parsedJournal.hasSummaryContent else {
            timelineContent = rawItems.isEmpty ? .empty : .raw(rawItems)
            return
        }

        let recentItems: [TimelineItem]
        if parsedJournal.hasNewerActivity {
            timelinePreparationStatus = .buildingRecentActivity
            recentItems = await Task.detached(priority: .userInitiated) {
                Self.buildTimelineItems(
                    rawEvents: rawEvents.filter { $0.endedAt > journal.updatedAt },
                    installedApplications: installedApplications
                )
            }.value
        } else {
            recentItems = []
        }

        guard Task.isCancelled == false else {
            return
        }

        timelinePreparationStatus = .finalizing
        timelineContent = .journal(
            document: parsedJournal.document,
            refreshedAt: journal.updatedAt,
            recentItems: recentItems
        )
    }

    nonisolated private static func parseJournalContent(
        journal: DailyJournal,
        rawEvents: [ActivityEvent],
        rawItems: [TimelineItem]
    ) -> ParsedJournalContent {
        let document = JournalMarkdownParser.parse(journal.markdown)
        let hasSummaryContent = document.leadingBlocks.isEmpty == false || document.sections.isEmpty == false
        let hasNewerActivity = hasSummaryContent && rawItems.isEmpty == false && rawEvents.contains {
            $0.isExcluded == false && $0.endedAt.timeIntervalSince(journal.updatedAt) > 10 * 60
        }

        return ParsedJournalContent(
            document: document,
            hasSummaryContent: hasSummaryContent,
            hasNewerActivity: hasNewerActivity
        )
    }

    nonisolated private static func buildTimelineItems(
        rawEvents: [ActivityEvent],
        installedApplications: [InstalledApplication]
    ) -> [TimelineItem] {
        let groupedRawEvents = ActivityEvidencePreprocessor.groupedMeaningfulEvents(from: rawEvents)
        let applicationsByBundleID = Dictionary(uniqueKeysWithValues: installedApplications.map {
            ($0.bundleID.lowercased(), $0)
        })

        return groupedRawEvents
            .filter { $0.isExcluded == false }
            .map { event in
                let bundlePath = applicationsByBundleID[event.bundleId.lowercased()]?.bundlePath
                let bulletCandidates: [String] = [
                    ActivityEvidencePreprocessor.summarizedURL(from: event.url),
                    event.excerpt.isEmpty ? nil : event.excerpt,
                    event.sourceEventCount > 1 ? "\(event.sourceEventCount) grouped logs" : nil,
                ].compactMap { value in
                    guard let value else { return nil }
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }

                return TimelineItem(
                    id: event.id,
                    timeRange: "\(OpenbirdDateFormatting.timeString(for: event.startedAt)) - \(OpenbirdDateFormatting.timeString(for: event.endedAt))",
                    title: event.displayTitle,
                    bullets: bulletCandidates,
                    bundleId: event.bundleId,
                    bundlePath: bundlePath,
                    appName: event.appName
                )
            }
    }
}

private enum TimelineContent: Sendable {
    case empty
    case journal(document: JournalMarkdownDocument, refreshedAt: Date, recentItems: [TimelineItem])
    case raw([TimelineItem])

    var isEmpty: Bool {
        switch self {
        case .empty:
            return true
        case .journal(let document, _, let recentItems):
            return (document.leadingBlocks.isEmpty && document.sections.isEmpty) && recentItems.isEmpty
        case .raw(let items):
            return items.isEmpty
        }
    }
}

private struct LoadingDisplayStatus: Equatable {
    let step: Int
    let totalSteps: Int
    let title: String
    let detail: String
}

private struct ParsedJournalContent: Sendable {
    let document: JournalMarkdownDocument
    let hasSummaryContent: Bool
    let hasNewerActivity: Bool
}

private enum TimelinePreparationStatus {
    case groupingActivity
    case parsingJournal
    case buildingRecentActivity
    case finalizing

    var displayStatus: LoadingDisplayStatus {
        switch self {
        case .groupingActivity:
            return LoadingDisplayStatus(
                step: 1,
                totalSteps: 4,
                title: "Grouping captured activity",
                detail: "Collapsing raw window snapshots into longer work blocks so the timeline is readable."
            )
        case .parsingJournal:
            return LoadingDisplayStatus(
                step: 2,
                totalSteps: 4,
                title: "Parsing the saved journal",
                detail: "Reading the cached markdown summary and checking whether newer activity arrived after it."
            )
        case .buildingRecentActivity:
            return LoadingDisplayStatus(
                step: 3,
                totalSteps: 4,
                title: "Building recent activity",
                detail: "Extracting the events captured since the last refresh so the latest work still shows up."
            )
        case .finalizing:
            return LoadingDisplayStatus(
                step: 4,
                totalSteps: 4,
                title: "Rendering the timeline",
                detail: "Matching app metadata, icons, and summary sections before the timeline is shown."
            )
        }
    }
}

private struct LoadingStatusCard: View {
    let status: LoadingDisplayStatus

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 8) {
                Text(status.title)
                    .font(.headline)

                StreamingStatusText(text: status.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            ProgressView(value: Double(status.step), total: Double(status.totalSteps))
                .frame(width: 260)

            Text("Step \(status.step) of \(status.totalSteps)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct StreamingStatusText: View {
    let text: String
    @State private var displayedText = ""

    var body: some View {
        Text(displayedText)
            .task(id: text) {
                await streamText(text)
            }
    }

    @MainActor
    private func streamText(_ text: String) async {
        displayedText = ""

        for character in text {
            guard Task.isCancelled == false else {
                return
            }

            displayedText.append(character)
            try? await Task.sleep(for: .milliseconds(12))
        }
    }
}

private struct TimelineItem: Identifiable, Sendable {
    let id: String
    let timeRange: String
    let title: String
    let bullets: [String]
    let bundleId: String?
    let bundlePath: String?
    let appName: String
}

private struct TimelinePreparationKey: Equatable {
    let journalID: String?
    let rawEventCount: Int
    let rawEventLastID: String?
    let installedApplicationCount: Int
}

private struct JournalMarkdownBlockView: View {
    let block: JournalMarkdownBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            JournalMarkdownText(
                markdown: text,
                font: .body,
                color: .primary
            )
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        JournalMarkdownText(
                            markdown: item,
                            font: .subheadline,
                            color: .secondary
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .table(let table):
            JournalMarkdownTableView(table: table)
        }
    }
}

private struct JournalMarkdownText: View {
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

private struct JournalMarkdownTableView: View {
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
                JournalMarkdownText(
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
