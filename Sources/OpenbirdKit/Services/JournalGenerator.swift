import Foundation
import OSLog

public actor JournalGenerator {
    private let store: OpenbirdStore
    private let logger = OpenbirdLog.journal

    private struct PreparedSection {
        let heading: String
        let timeRange: String
        let bullets: [String]
        let groupedEvents: [GroupedActivityEvent]

        var journalSection: JournalSection {
            JournalSection(
                heading: heading,
                timeRange: timeRange,
                bullets: bullets,
                sourceEventIDs: groupedEvents.flatMap(\.sourceEventIDs)
            )
        }
    }

    public init(store: OpenbirdStore) {
        self.store = store
    }

    public func generate(request: JournalGenerationRequest) async throws -> DailyJournal {
        let day = OpenbirdDateFormatting.dayString(for: request.date)
        let dayRange = Calendar.current.dayRange(for: request.date)
        let events = try await store.loadActivityEvents(in: dayRange)
        let groupedEvents = Array(
            ActivityEvidencePreprocessor.groupedMeaningfulEvents(from: events)
                .prefix(request.maxSourceEvents)
        )
        let preparedSections = buildSections(from: groupedEvents)
        let sections = preparedSections.map(\.journalSection)
        let heuristicMarkdown = renderMarkdown(for: request.date, sections: preparedSections)
        logger.notice(
            "Generating journal for \(day, privacy: .public); events=\(events.count, privacy: .public) sections=\(preparedSections.count, privacy: .public)"
        )

        let providerConfig = try await activeProviderIfAvailable(id: request.providerID)
        let markdown: String
        if let providerConfig {
            do {
                let provider = ProviderFactory.makeProvider(for: providerConfig)
                let prompt = journalPrompt(for: request.date, sections: preparedSections)
                let response = try await provider.chat(
                    request: ProviderChatRequest(
                        messages: [
                            ChatTurn(
                                role: .system,
                                content: "Write polished markdown only. Sound like a grounded assistant recapping the day after reviewing context, not a timeline dump or changelog."
                            ),
                            ChatTurn(role: .user, content: prompt),
                        ]
                    )
                )
                markdown = response.content.isEmpty ? heuristicMarkdown : response.content
                logger.notice("Generated journal with provider kind=\(providerConfig.kind.rawValue, privacy: .public)")
            } catch {
                logger.error(
                    "Provider journal generation failed; using heuristic journal. kind=\(providerConfig.kind.rawValue, privacy: .public) error=\(OpenbirdLog.errorDescription(error), privacy: .public)"
                )
                markdown = heuristicMarkdown
            }
        } else {
            logger.notice("No active provider configured; using heuristic journal")
            markdown = heuristicMarkdown
        }

        let journal = DailyJournal(
            day: day,
            markdown: markdown,
            sections: sections,
            providerID: providerConfig?.id,
            updatedAt: Date()
        )
        try await store.saveJournal(journal)
        logger.notice("Saved journal for \(day, privacy: .public)")
        return journal
    }

    private func activeProviderIfAvailable(id: String?) async throws -> ProviderConfig? {
        let settings = try await store.loadSettings()
        let configs = try await store.loadProviderConfigs()
        return ProviderSelection.resolve(configs: configs, settings: settings, preferredID: id)
    }

    private func buildSections(from events: [GroupedActivityEvent]) -> [PreparedSection] {
        guard events.isEmpty == false else { return [] }
        var groups: [[GroupedActivityEvent]] = [[events[0]]]
        for event in events.dropFirst() {
            guard let previous = groups[groups.count - 1].last else { continue }
            let gap = event.startedAt.timeIntervalSince(previous.endedAt)
            if gap > 20 * 60 || event.bundleId != previous.bundleId {
                groups.append([event])
            } else {
                groups[groups.count - 1].append(event)
            }
        }

        return groups.map { group in
            let dominant = preferredHeading(in: group)
            let bullets = group
                .map(makeBullet(for:))
                .filter { $0.isEmpty == false }
                .deduplicatedByNormalizedText()
                .prefix(4)
            let start = OpenbirdDateFormatting.timeString(for: group.first?.startedAt ?? Date())
            let end = OpenbirdDateFormatting.timeString(for: group.last?.endedAt ?? Date())
            return PreparedSection(
                heading: dominant,
                timeRange: "\(start) - \(end)",
                bullets: Array(bullets),
                groupedEvents: group
            )
        }
    }

    private func makeBullet(for event: GroupedActivityEvent) -> String {
        var pieces = [event.appName]
        if let detailTitle = event.detailTitle {
            pieces.append(detailTitle)
        }
        if let urlSummary = ActivityEvidencePreprocessor.summarizedURL(from: event.url) {
            pieces.append(urlSummary)
        }
        if event.excerpt.isEmpty == false {
            pieces.append(event.excerpt)
        }
        return pieces.deduplicatedByNormalizedText().joined(separator: " • ")
    }

    private func sectionPrompt(_ section: PreparedSection) -> String {
        let evidence = section.groupedEvents
            .map(eventPrompt)
            .joined(separator: "\n")
        let appList = Array(section.groupedEvents.map(\.appName).deduplicatedByNormalizedText())

        return """
        Raw evidence chunk
        Time window: \(section.timeRange)
        Raw label candidate (do not copy blindly): \(section.heading)
        Apps involved: \(naturalLanguageList(appList))
        Interpretation guidance:
        - Describe what the user was trying to do, decide, compare, write, debug, or follow up on.
        - Do not use a bare tool, site, repo, or channel name as the heading when a task-level description is possible.
        - This chunk can be merged with adjacent chunks if they belong to the same broader activity.
        Evidence:
        \(evidence.isEmpty ? "- No detailed evidence available." : evidence)
        """
    }

    private func journalPrompt(for date: Date, sections: [PreparedSection]) -> String {
        """
        You are writing Openbird's daily activity summary from local computer activity logs.
        Write for the person who lived the day.

        Your job is to reconstruct the user's day in the style of a smart recap, not to restate obvious app switches.

        Requirements:
        - Return markdown only.
        - Do not include a document title or repeat the date as a top heading.
        - Start with a short context line such as `Looked through your context.`.
        - Follow with 1 short framing paragraph that captures the overall shape of the day when possible.
        - Then write 3-6 chronological sections using markdown `##` headings.
        - Section headings should feel human and synthesis-first. Prefer titles like `Work & Dev`, `Research & Reading`, `Social & Comms`, `Morning (~8:30 - 9 AM)`, or `Evening Wrap-Up` over raw timestamps.
        - It is okay to mix styles when the evidence supports it: some sections can be category-based, others can be time-bucketed.
        - Headings must describe the user's likely task, intent, or outcome. Avoid headings that are just tool names, URLs, repo names, or channel names unless there is truly no better inference.
        - Treat the evidence as raw fragments, not as a required one-fragment-per-section outline. Merge adjacent chunks into a broader section when they are clearly part of the same work mode, project, research thread, or detour.
        - Favor chapter-like section titles such as `Code Grind`, `Strategy Call`, `Hardware Window Shopping`, `YC Demo Day`, or `Browsing & Twitter` when the evidence supports that level of synthesis.
        - Under each heading, write 1 short paragraph that explains what happened, why it mattered, or what the user was trying to figure out.
        - If a section covers multiple concrete items, repos, people, PRs, or threads, add 2-5 bullets under that section to surface the most interesting specifics.
        - Favor verbs like comparing, researching, drafting, reviewing, coordinating, debugging, planning, or replying when the evidence supports them.
        - Mention apps, repos, people, channels, or pages only when they help identify the work. They are supporting detail, not the main point.
        - Merge or omit low-signal noise instead of narrating every app switch.
        - Synthesize the evidence instead of echoing it verbatim.
        - Prefer meaningful work descriptions over app chrome, repeated browser controls, toolbar labels, or duplicated URLs.
        - Add bullet lists only when they improve clarity, such as decisions, people, deliverables, comparisons, PRs, or candidate lists.
        - Use a markdown table when the evidence clearly contains a compact status list, comparison, or set of PRs.
        - A short closing observation or `**TL;DR:**` line is allowed when it sharpens the recap.
        - Keep the tone observant and concise. Slight personality is fine, but do not sound gushy, generic, or like an app changelog.
        - If the evidence is noisy or ambiguous, hedge briefly instead of inventing detail.

        Response shape:
        Looked through your context.

        <one short framing paragraph>

        ## <human section title>
        <one short paragraph>
        - <optional specific>
        - <optional specific>

        ## <next human section title>
        <one short paragraph>

        Bad headings:
        - `## 8:37 AM - Slack`
        - `## 12:00 AM - Safari`
        - `## 2:10 PM - stilla.ai`

        Better headings:
        - `## Checking the judging channel for next steps`
        - `## Comparing AI meeting-note tools`
        - `## Reviewing pricing and positioning for Stilla`
        - `## Work & Dev`
        - `## Research & Reading`
        - `## Morning (~8:30 - 9 AM)`
        - `## Hardware Window Shopping`
        - `## YouTube Deep Dive`

        Day: \(OpenbirdDateFormatting.weekdayFormatter.string(from: date))

        Evidence:
        \(sections.map(sectionPrompt).joined(separator: "\n\n"))
        """
    }

    private func eventPrompt(_ event: GroupedActivityEvent) -> String {
        var pieces = [
            "\(OpenbirdDateFormatting.timeString(for: event.startedAt))-\(OpenbirdDateFormatting.timeString(for: event.endedAt))",
            event.appName,
        ]

        if let detailTitle = event.detailTitle {
            pieces.append(detailTitle)
        }

        if let urlSummary = ActivityEvidencePreprocessor.summarizedURL(from: event.url) {
            pieces.append(urlSummary)
        }

        if event.excerpt.isEmpty == false {
            pieces.append(event.excerpt)
        }

        if event.sourceEventCount > 1 {
            pieces.append("\(event.sourceEventCount) grouped logs")
        }

        return "- " + pieces.joined(separator: " | ")
    }

    private func renderMarkdown(for date: Date, sections: [PreparedSection]) -> String {
        guard sections.isEmpty == false else {
            return """
            Looked through your context.

            No meaningful activity captured yet for \(OpenbirdDateFormatting.weekdayFormatter.string(from: date)).
            """
        }

        var markdown = """
        Looked through your context.

        \(summaryFramingParagraph(for: date, sections: sections))

        """
        for section in sections {
            markdown += "## \(sectionHeading(for: section))\n\n"
            markdown += sectionNarrative(for: section)
            let bullets = sectionBulletItems(for: section)
            if bullets.isEmpty == false {
                markdown += "\n\n"
                markdown += bullets.map { "- \($0)" }.joined(separator: "\n")
            }
            markdown += "\n\n"
        }
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func summaryFramingParagraph(for date: Date, sections: [PreparedSection]) -> String {
        let weekday = OpenbirdDateFormatting.weekdayFormatter.string(from: date)

        switch sections.count {
        case 0:
            return "No meaningful activity captured yet for \(weekday)."
        case 1:
            return "Here's the clearest thread from your \(weekday)."
        case 5...:
            return "Busy \(weekday). Here's the shape of it."
        default:
            return "Here's the shape of your \(weekday)."
        }
    }

    private func preferredHeading(in group: [GroupedActivityEvent]) -> String {
        guard let appName = group.first?.appName else { return "Activity" }

        let ranked = group.reduce(into: [String: Int]()) { counts, event in
            let title = event.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.isEmpty == false else { return }

            var score = 1
            if title.normalizedComparisonKey != appName.normalizedComparisonKey {
                score += 4
            }
            if title.count > appName.count {
                score += 1
            }

            counts[title, default: 0] += score
        }
        return ranked.max(by: { $0.value < $1.value })?.key ?? appName
    }

    private func sectionHeading(for section: PreparedSection) -> String {
        storyHeadingLabel(for: section)
    }

    private func sectionNarrative(for section: PreparedSection) -> String {
        let apps = Array(section.groupedEvents.map(\.appName).deduplicatedByNormalizedText())
        let topic = displayTopic(for: section)
        let topicKey = topic.normalizedComparisonKey
        let appKeys = Set(apps.map(\.normalizedComparisonKey))

        var sentences: [String] = []
        if let narrativeLead = storyNarrativeLead(for: section, apps: apps) {
            sentences.append(narrativeLead)
        } else if appKeys.contains(topicKey) {
            sentences.append("You spent time in \(naturalLanguageList(apps)).")
        } else if apps.isEmpty {
            sentences.append("This part of the day centered on \(topic).")
        } else {
            sentences.append("This part of the day centered on \(topic) in \(naturalLanguageList(apps)).")
        }

        let highlights = sectionHighlights(for: section)
        if highlights.count == 1, let highlight = highlights.first {
            sentences.append("The main detail was \(highlight).")
        }

        return sentences.joined(separator: " ")
    }

    private func sectionBulletItems(for section: PreparedSection) -> [String] {
        let highlights = sectionHighlights(for: section)
        guard highlights.count > 1 else {
            return []
        }

        return Array(highlights.prefix(4))
    }

    private func displayTopic(for section: PreparedSection) -> String {
        let topic = section.heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard topic.isEmpty == false else {
            return section.groupedEvents.first?.appName ?? "Activity"
        }

        return topic
    }

    private func storyHeadingLabel(for section: PreparedSection) -> String {
        let topic = displayTopic(for: section)
        guard shouldRewriteHeading(topic, section: section),
              let context = bestStoryContext(for: section) else {
            return topic
        }

        switch dominantCategory(for: section) {
        case .browser:
            return "Reviewing \(context)"
        case .communication:
            return "Following up in \(context)"
        case .development:
            return "Working on \(context)"
        case .generic:
            return "Working through \(context)"
        }
    }

    private func storyNarrativeLead(for section: PreparedSection, apps: [String]) -> String? {
        guard shouldRewriteHeading(displayTopic(for: section), section: section),
              let context = bestStoryContext(for: section) else {
            return nil
        }

        switch dominantCategory(for: section) {
        case .browser:
            return "You were reviewing \(context) in \(naturalLanguageList(apps))."
        case .communication:
            return "You were following up in \(context) through \(naturalLanguageList(apps))."
        case .development:
            return "You were working on \(context) in \(naturalLanguageList(apps))."
        case .generic:
            return "You were working through \(context) in \(naturalLanguageList(apps))."
        }
    }

    private func shouldRewriteHeading(_ topic: String, section: PreparedSection) -> Bool {
        let normalizedTopic = topic.normalizedComparisonKey
        guard normalizedTopic.isEmpty == false else {
            return true
        }

        let appNames = Set(section.groupedEvents.map { $0.appName.normalizedComparisonKey })
        if appNames.contains(normalizedTopic) {
            return true
        }

        return genericToolLabels.contains(normalizedTopic)
    }

    private func bestStoryContext(for section: PreparedSection) -> String? {
        let topicKey = displayTopic(for: section).normalizedComparisonKey

        let detailTitles = section.groupedEvents
            .compactMap(\.detailTitle)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                $0.isEmpty == false &&
                $0.normalizedComparisonKey != topicKey &&
                genericToolLabels.contains($0.normalizedComparisonKey) == false
            }
        if let detailTitle = detailTitles.first {
            return detailTitle
        }

        let urls = section.groupedEvents
            .compactMap(\.url)
            .compactMap(ActivityEvidencePreprocessor.summarizedURL(from:))
            .filter { $0.isEmpty == false }
        if let url = urls.first {
            return url
        }

        let highlights = sectionHighlights(for: section)
        if let highlight = highlights.first(where: { $0.split(separator: " ").count >= 2 }) {
            return highlight
        }

        return nil
    }

    private func dominantCategory(for section: PreparedSection) -> ActivityCategory {
        let appNames = Set(section.groupedEvents.map { $0.appName.normalizedComparisonKey })
        if appNames.isDisjoint(with: browserAppLabels) == false {
            return .browser
        }
        if appNames.isDisjoint(with: communicationAppLabels) == false {
            return .communication
        }
        if appNames.isDisjoint(with: developmentAppLabels) == false {
            return .development
        }
        return .generic
    }

    private func sectionHighlights(for section: PreparedSection) -> [String] {
        let excludedLabels = [section.heading] + section.groupedEvents.map(\.appName)
        let excluded = Set(excludedLabels.map(\.normalizedComparisonKey))

        var pieces: [String] = []
        for bullet in section.bullets {
            for segment in bullet.split(separator: "•") {
                let piece = trimmedHighlight(
                    from: segment.trimmingCharacters(in: .whitespacesAndNewlines),
                    removingLeadingLabels: excludedLabels
                )
                guard piece.isEmpty == false else { continue }
                guard excluded.contains(piece.normalizedComparisonKey) == false else { continue }
                pieces.append(piece)
            }
        }

        return Array(pieces.deduplicatedByNormalizedText().prefix(3))
    }

    private func trimmedHighlight(
        from piece: String,
        removingLeadingLabels labels: [String]
    ) -> String {
        var candidate = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.isEmpty == false else {
            return ""
        }

        let normalizedLabels = labels
            .map(\.normalizedComparisonKey)
            .filter { $0.isEmpty == false }
            .sorted { $0.count > $1.count }

        while true {
            let words = candidate.split(separator: " ")
            var strippedAnyLabel = false

            for label in normalizedLabels {
                let labelWords = label.split(separator: " ")
                guard words.count > labelWords.count else {
                    continue
                }

                let prefix = words
                    .prefix(labelWords.count)
                    .map(String.init)
                    .joined(separator: " ")
                    .normalizedComparisonKey

                guard prefix == label else {
                    continue
                }

                candidate = words.dropFirst(labelWords.count).joined(separator: " ")
                strippedAnyLabel = true
                break
            }

            if strippedAnyLabel == false {
                break
            }
        }

        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func naturalLanguageList(_ values: [String]) -> String {
        switch values.count {
        case 0:
            return "activity"
        case 1:
            return values[0]
        case 2:
            return "\(values[0]) and \(values[1])"
        default:
            let prefix = values.dropLast().joined(separator: ", ")
            return "\(prefix), and \(values[values.count - 1])"
        }
    }

    private enum ActivityCategory {
        case browser
        case communication
        case development
        case generic
    }

    private var browserAppLabels: Set<String> {
        ["safari", "google chrome", "chrome", "arc", "firefox", "brave", "microsoft edge", "edge"]
    }

    private var communicationAppLabels: Set<String> {
        ["slack", "messages", "imessage", "discord", "kakaotalk", "telegram", "whatsapp", "mail", "gmail"]
    }

    private var developmentAppLabels: Set<String> {
        ["xcode", "visual studio code", "vs code", "cursor", "zed", "terminal", "iterm2", "warp", "nova"]
    }

    private var genericToolLabels: Set<String> {
        browserAppLabels
            .union(communicationAppLabels)
            .union(developmentAppLabels)
            .union(["finder", "notes", "calendar", "notion", "figma", "linear"])
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
