import Foundation

public actor JournalGenerator {
    private let store: OpenbirdStore

    public init(store: OpenbirdStore) {
        self.store = store
    }

    public func generate(request: JournalGenerationRequest) async throws -> DailyJournal {
        let dayRange = Calendar.current.dayRange(for: request.date)
        let events = try await store.loadActivityEvents(in: dayRange)
        let trimmedEvents = Array(events.prefix(request.maxSourceEvents))
        let sections = buildSections(from: trimmedEvents)
        let eventsByID = Dictionary(uniqueKeysWithValues: trimmedEvents.map { ($0.id, $0) })
        let heuristicMarkdown = renderMarkdown(for: request.date, sections: sections, events: trimmedEvents)

        let providerConfig = try await activeProviderIfAvailable(id: request.providerID)
        let markdown: String
        if let providerConfig {
            do {
                let provider = ProviderFactory.makeProvider(for: providerConfig)
                let prompt = """
                You are writing a useful daily activity review from local computer activity logs.
                Write for the person who lived the day.

                Requirements:
                - Return markdown only.
                - Do not include a document title or repeat the date as a top heading.
                - Start with a short framing sentence only if it adds value.
                - Then write 4-8 chronological sections using markdown `##` headings.
                - Each section heading should combine the approximate time or time range with the activity, for example `## ~3:15 PM - 4:15 PM - Char Dev Sprint`.
                - Under each heading, write 1 short paragraph that explains what happened, with concrete nouns and outcomes.
                - Add bullet lists only when they improve clarity, such as decisions, people, deliverables, or candidate lists.
                - Use a markdown table when the evidence clearly contains a compact status list, comparison, or set of PRs.
                - Merge or omit low-signal noise instead of narrating every app switch.
                - Synthesize the evidence instead of echoing it verbatim.
                - Prefer meaningful work descriptions over app chrome, repeated browser controls, toolbar labels, or duplicated URLs.
                - Mention apps, repos, people, channels, or pages only when they help identify the work.
                - If the evidence is noisy or ambiguous, say so briefly instead of inventing detail.

                Day: \(OpenbirdDateFormatting.weekdayFormatter.string(from: request.date))

                Evidence:
                \(sections.map { sectionPrompt($0, eventsByID: eventsByID) }.joined(separator: "\n\n"))
                """
                let response = try await provider.chat(
                    request: ProviderChatRequest(
                        messages: [
                            ChatTurn(role: .system, content: "Write polished markdown only."),
                            ChatTurn(role: .user, content: prompt),
                        ]
                    )
                )
                markdown = response.content.isEmpty ? heuristicMarkdown : response.content
            } catch {
                markdown = heuristicMarkdown
            }
        } else {
            markdown = heuristicMarkdown
        }

        let journal = DailyJournal(
            day: OpenbirdDateFormatting.dayString(for: request.date),
            markdown: markdown,
            sections: sections,
            providerID: providerConfig?.id,
            updatedAt: Date()
        )
        try await store.saveJournal(journal)
        return journal
    }

    private func activeProviderIfAvailable(id: String?) async throws -> ProviderConfig? {
        let configs = try await store.loadProviderConfigs().filter(\.isEnabled)
        if let id {
            return configs.first { $0.id == id }
        }
        let settings = try await store.loadSettings()
        if let activeID = settings.activeProviderID {
            return configs.first { $0.id == activeID }
        }
        return configs.first
    }

    private func buildSections(from events: [ActivityEvent]) -> [JournalSection] {
        guard events.isEmpty == false else { return [] }
        var groups: [[ActivityEvent]] = [[events[0]]]
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
            return JournalSection(
                heading: dominant,
                timeRange: "\(start) - \(end)",
                bullets: Array(bullets),
                sourceEventIDs: group.map(\.id)
            )
        }
    }

    private func makeBullet(for event: ActivityEvent) -> String {
        var pieces = [event.appName]
        if let detailTitle = event.detailTitle {
            pieces.append(detailTitle)
        }
        if let urlSummary = summarizedURL(from: event.url) {
            pieces.append(urlSummary)
        }
        if event.excerpt.isEmpty == false {
            pieces.append(event.excerpt)
        }
        return pieces.deduplicatedByNormalizedText().joined(separator: " • ")
    }

    private func sectionPrompt(
        _ section: JournalSection,
        eventsByID: [String: ActivityEvent]
    ) -> String {
        let evidence = section.sourceEventIDs
            .compactMap { eventsByID[$0] }
            .map(eventPrompt)
            .joined(separator: "\n")

        return """
        Focus window: \(section.timeRange)
        Likely topic: \(section.heading)
        Evidence:
        \(evidence.isEmpty ? "- No detailed evidence available." : evidence)
        """
    }

    private func eventPrompt(_ event: ActivityEvent) -> String {
        var pieces = [
            "\(OpenbirdDateFormatting.timeString(for: event.startedAt))-\(OpenbirdDateFormatting.timeString(for: event.endedAt))",
            event.appName,
        ]

        if let detailTitle = event.detailTitle {
            pieces.append(detailTitle)
        }

        if let urlSummary = summarizedURL(from: event.url) {
            pieces.append(urlSummary)
        }

        if event.excerpt.isEmpty == false {
            pieces.append(event.excerpt)
        }

        return "- " + pieces.joined(separator: " | ")
    }

    private func renderMarkdown(for date: Date, sections: [JournalSection], events: [ActivityEvent]) -> String {
        guard sections.isEmpty == false else {
            return "No activity captured yet for \(OpenbirdDateFormatting.weekdayFormatter.string(from: date))."
        }

        let appCount = Set(events.map(\.appName)).count
        var markdown = "Captured \(sections.count) focus block\(sections.count == 1 ? "" : "s") across \(appCount) app\(appCount == 1 ? "" : "s") on \(OpenbirdDateFormatting.weekdayFormatter.string(from: date)).\n\n"
        for section in sections {
            markdown += "## \(section.timeRange) — \(section.heading)\n\n"
            markdown += section.bullets.map { "- \($0)" }.joined(separator: "\n")
            markdown += "\n\n"
        }
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func preferredHeading(in group: [ActivityEvent]) -> String {
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

    private func summarizedURL(from urlString: String?) -> String? {
        guard let urlString,
              urlString.isEmpty == false
        else {
            return nil
        }

        guard let components = URLComponents(string: urlString),
              let host = components.host
        else {
            return String(urlString.prefix(80))
        }

        let normalizedHost = host.replacingOccurrences(of: "www.", with: "")
        let path = components.path == "/" ? "" : components.path
        let summary = normalizedHost + path

        if summary.isEmpty {
            return normalizedHost
        }

        return summary.count > 80 ? String(summary.prefix(80)) + "…" : summary
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
