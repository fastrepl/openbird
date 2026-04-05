import SwiftUI
import OpenbirdKit

struct TodayView: View {
    @ObservedObject var model: AppModel
    @State private var timelineContent: TimelineContent = .empty
    @State private var isPreparingTimeline = false
    @State private var timelinePreparationStatus: TimelinePreparationStatus?
    @State private var selectedTimelineMode: TodayTimelineMode = .topic
    @State private var isChatExpanded = false
    @FocusState private var focusedField: TodayChatDock.FocusField?
    private let collapsedChatClearance: CGFloat = 92
    private let expandedChatClearance: CGFloat = 420
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if availableTimelineModes.count > 1 {
                HStack {
                    Spacer()
                    timelineModePicker
                        .frame(width: 240)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
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
                    Text(model.isGeneratingTodayJournal ? inFlightJournalActionTitle : journalActionTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isGeneratingTodayJournal)
        }
    }

    private var timelineModePicker: some View {
        Picker("View", selection: $selectedTimelineMode) {
            ForEach(availableTimelineModes, id: \.self) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var timelineView: some View {
        switch timelineContent {
        case .empty:
            EmptyView()
        case .journal(let document, let refreshedAt, let recentSection, let timelineSection):
            switch activeTimelineMode {
            case .topic:
                journalTimeline(document: document, refreshedAt: refreshedAt, recentSection: recentSection)
            case .timeline:
                timelineCard(section: timelineSection)
            case nil:
                EmptyView()
            }
        case .raw(let section):
            timelineCard(section: section)
        }
    }

    private func journalTimeline(
        document: JournalMarkdownDocument,
        refreshedAt: Date,
        recentSection: TimelineSection
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                if document.leadingBlocks.isEmpty == false {
                    MarkdownBlocksView(
                        blocks: document.leadingBlocks,
                        paragraphFont: .body,
                        paragraphColor: .primary,
                        listFont: .subheadline,
                        listColor: .secondary
                    )
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

                        MarkdownBlocksView(
                            blocks: section.blocks,
                            paragraphFont: .body,
                            paragraphColor: .primary,
                            listFont: .subheadline,
                            listColor: .secondary
                        )
                    }
                    .padding(24)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 24))

            if recentSection.isEmpty == false {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Activity")
                        .font(.headline)
                    Text("Summary last refreshed at \(OpenbirdDateFormatting.timeString(for: refreshedAt)). Newer captured activity is shown below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    timelineCard(section: recentSection)
                }
            }
        }
    }

    private func timelineCard(section: TimelineSection) -> some View {
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(section.insights.enumerated()), id: \.element.id) { index, insight in
                if index > 0 {
                    Divider()
                }
                timelineInsightRow(insight)
                    .padding(24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
    }

    private func timelineInsightRow(_ insight: TimelineInsightGroup) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(insightAccentColor(for: insight.kind).opacity(0.14))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: insight.kind.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(insightAccentColor(for: insight.kind))
                }

            VStack(alignment: .leading, spacing: 8) {
                Text(insight.title)
                    .font(.headline)

                Text(insight.metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(insight.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if insight.apps.isEmpty == false {
                    Text("Apps: \(insight.apps.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                ForEach(insight.highlights, id: \.self) { highlight in
                    Text("• \(highlight)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func insightAccentColor(for kind: TimelineInsightKind) -> Color {
        switch kind {
        case .communication:
            return .blue
        case .development:
            return .orange
        case .planning:
            return .indigo
        case .research:
            return .mint
        case .admin:
            return .gray
        case .media:
            return .pink
        case .generic:
            return .accentColor
        }
    }

    private var timelinePreparationKey: TimelinePreparationKey {
        TimelinePreparationKey(
            journalID: model.todayJournal?.id,
            rawEventCount: model.rawEvents.count,
            rawEventLastID: model.rawEvents.last?.id,
            installedApplicationCount: model.installedApplications.count
        )
    }

    private var availableTimelineModes: [TodayTimelineMode] {
        timelineContent.availableModes
    }

    private var activeTimelineMode: TodayTimelineMode? {
        TodayTimelineMode.resolvedSelection(
            selectedTimelineMode,
            hasJournalContent: timelineContent.hasJournalContent,
            hasTimelineItems: timelineContent.hasTimelineItems
        )
    }

    private var journalActionTitle: String {
        model.todayJournal == nil ? "Generate" : "Refresh"
    }

    private var inFlightJournalActionTitle: String {
        model.todayJournal == nil ? "Generating…" : "Refreshing…"
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
        let day = Calendar.autoupdatingCurrent.component(.day, from: model.selectedDay)
        let month = Self.selectedDayMonthString(for: model.selectedDay)
        let year = Self.selectedDayYearString(for: model.selectedDay)
        return "\(month) \(day)\(ordinalSuffix(for: day)), \(year)"
    }

    private var isShowingToday: Bool {
        Calendar.autoupdatingCurrent.isDate(model.selectedDay, inSameDayAs: Date())
    }

    private func stepSelectedDay(by offset: Int) {
        let calendar = Calendar.autoupdatingCurrent
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

    private static func selectedDayMonthString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }

    private static func selectedDayYearString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    @MainActor
    private func prepareTimeline() async {
        let journal = model.todayJournal
        let rawEvents = model.rawEvents
        let installedApplications = model.installedApplications
        let rawSectionTask = Task.detached(priority: .userInitiated) {
            Self.buildTimelineSection(
                rawEvents: rawEvents,
                installedApplications: installedApplications
            )
        }

        isPreparingTimeline = true
        timelinePreparationStatus = .groupingActivity
        defer {
            isPreparingTimeline = false
            timelinePreparationStatus = nil
        }

        guard let journal else {
            let rawSection = await rawSectionTask.value

            guard Task.isCancelled == false else {
                return
            }

            timelineContent = rawSection.isEmpty ? .empty : .raw(rawSection)
            return
        }

        timelinePreparationStatus = .parsingJournal
        let parsedJournal = await Task.detached(priority: .userInitiated) {
            Self.parseJournalContent(
                journal: journal,
                rawEvents: rawEvents
            )
        }.value

        guard Task.isCancelled == false else {
            return
        }

        let rawSection = await rawSectionTask.value

        guard Task.isCancelled == false else {
            return
        }

        guard parsedJournal.hasSummaryContent else {
            timelineContent = rawSection.isEmpty ? .empty : .raw(rawSection)
            return
        }

        let recentSection: TimelineSection
        if parsedJournal.hasNewerActivity {
            timelinePreparationStatus = .buildingRecentActivity
            let recentItems = Self.recentTimelineItems(
                from: rawSection.items,
                matching: Set(parsedJournal.uncompiledRawEvents.map(\.id))
            )
            recentSection = await Task.detached(priority: .userInitiated) {
                TimelineSection.build(from: recentItems)
            }.value
        } else {
            recentSection = .empty
        }

        guard Task.isCancelled == false else {
            return
        }

        timelinePreparationStatus = .finalizing
        timelineContent = .journal(
            document: parsedJournal.document,
            refreshedAt: journal.updatedAt,
            recentSection: recentSection,
            timelineSection: rawSection
        )
    }

    nonisolated private static func parseJournalContent(
        journal: DailyJournal,
        rawEvents: [ActivityEvent]
    ) -> ParsedJournalContent {
        let document = JournalMarkdownParser.parse(journal.markdown)
        let hasSummaryContent = document.leadingBlocks.isEmpty == false || document.sections.isEmpty == false
        let uncompiledRawEvents = hasSummaryContent
            ? AppModel.uncompiledActivityEvents(from: rawEvents, comparedTo: journal)
            : []

        return ParsedJournalContent(
            document: document,
            hasSummaryContent: hasSummaryContent,
            uncompiledRawEvents: uncompiledRawEvents
        )
    }

    nonisolated private static func buildTimelineSection(
        rawEvents: [ActivityEvent],
        installedApplications: [InstalledApplication]
    ) -> TimelineSection {
        let groupedRawEvents = ActivityEvidencePreprocessor.groupedMeaningfulEvents(from: rawEvents)
        let applicationsByBundleID = Dictionary(uniqueKeysWithValues: installedApplications.map {
            ($0.bundleID.lowercased(), $0)
        })

        let items = groupedRawEvents
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
                    startedAt: event.startedAt,
                    endedAt: event.endedAt,
                    title: event.displayTitle,
                    bullets: bulletCandidates,
                    sourceEventIDs: event.sourceEventIDs,
                    bundleId: event.bundleId,
                    bundlePath: bundlePath,
                    appName: event.appName
                )
            }

        return TimelineSection.build(from: items)
    }

    nonisolated private static func recentTimelineItems(
        from items: [TimelineItem],
        matching sourceEventIDs: Set<String>
    ) -> [TimelineItem] {
        guard sourceEventIDs.isEmpty == false else {
            return []
        }

        return items.filter { item in
            item.sourceEventIDs.contains { sourceEventIDs.contains($0) }
        }
    }
}

struct TimelineSection: Sendable {
    let items: [TimelineItem]
    let insights: [TimelineInsightGroup]

    static let empty = TimelineSection(items: [], insights: [])

    var isEmpty: Bool {
        items.isEmpty
    }

    static func build(from items: [TimelineItem]) -> TimelineSection {
        TimelineSection(
            items: items,
            insights: TimelineInsightBuilder.build(from: items)
        )
    }
}

private enum TimelineContent: Sendable {
    case empty
    case journal(document: JournalMarkdownDocument, refreshedAt: Date, recentSection: TimelineSection, timelineSection: TimelineSection)
    case raw(TimelineSection)

    var isEmpty: Bool {
        switch self {
        case .empty:
            return true
        case .journal(let document, _, _, let timelineSection):
            return (document.leadingBlocks.isEmpty && document.sections.isEmpty) && timelineSection.isEmpty
        case .raw(let section):
            return section.isEmpty
        }
    }

    var hasJournalContent: Bool {
        guard case .journal(let document, _, _, _) = self else {
            return false
        }

        return document.leadingBlocks.isEmpty == false || document.sections.isEmpty == false
    }

    var hasTimelineItems: Bool {
        switch self {
        case .empty:
            return false
        case .journal(_, _, _, let timelineSection):
            return timelineSection.isEmpty == false
        case .raw(let section):
            return section.isEmpty == false
        }
    }

    var availableModes: [TodayTimelineMode] {
        TodayTimelineMode.availableModes(
            hasJournalContent: hasJournalContent,
            hasTimelineItems: hasTimelineItems
        )
    }
}

enum TodayTimelineMode: Hashable {
    case topic
    case timeline

    var title: String {
        switch self {
        case .topic:
            return "Topic"
        case .timeline:
            return "Timeline"
        }
    }

    static func availableModes(
        hasJournalContent: Bool,
        hasTimelineItems: Bool
    ) -> [TodayTimelineMode] {
        var modes: [TodayTimelineMode] = []

        if hasJournalContent {
            modes.append(.topic)
        }

        if hasTimelineItems {
            modes.append(.timeline)
        }

        return modes
    }

    static func resolvedSelection(
        _ selection: TodayTimelineMode,
        hasJournalContent: Bool,
        hasTimelineItems: Bool
    ) -> TodayTimelineMode? {
        let availableModes = availableModes(
            hasJournalContent: hasJournalContent,
            hasTimelineItems: hasTimelineItems
        )

        guard availableModes.isEmpty == false else {
            return nil
        }

        return availableModes.contains(selection) ? selection : availableModes[0]
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
    let uncompiledRawEvents: [ActivityEvent]

    var hasNewerActivity: Bool {
        uncompiledRawEvents.isEmpty == false
    }
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
                detail: "Turning grouped activity into higher-level insight cards before the timeline is shown."
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

private struct TimelinePreparationKey: Equatable {
    let journalID: String?
    let rawEventCount: Int
    let rawEventLastID: String?
    let installedApplicationCount: Int
}
