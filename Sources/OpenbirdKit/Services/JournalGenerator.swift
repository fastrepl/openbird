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
        let heuristicMarkdown = renderMarkdown(for: request.date, sections: sections, events: trimmedEvents)

        let providerConfig = try await activeProviderIfAvailable(id: request.providerID)
        let markdown: String
        if let providerConfig {
            do {
                let provider = ProviderFactory.makeProvider(for: providerConfig)
                let prompt = """
                You are writing a concise, factual daily activity journal from local computer activity logs.
                Group the day into readable sections with headings and 1-4 bullets per section.
                Avoid inventing details. Use only the evidence provided.

                Day: \(OpenbirdDateFormatting.weekdayFormatter.string(from: request.date))

                Evidence:
                \(sections.map(sectionPrompt).joined(separator: "\n\n"))
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
            let titles = group.map(\.displayTitle).filter { $0.isEmpty == false }
            let dominant = mostFrequentString(in: titles) ?? group.first?.appName ?? "Activity"
            let bullets = Array(group.prefix(4)).map(makeBullet(for:))
            let start = OpenbirdDateFormatting.timeString(for: group.first?.startedAt ?? Date())
            let end = OpenbirdDateFormatting.timeString(for: group.last?.endedAt ?? Date())
            return JournalSection(
                heading: dominant,
                timeRange: "\(start) - \(end)",
                bullets: bullets,
                sourceEventIDs: group.map(\.id)
            )
        }
    }

    private func makeBullet(for event: ActivityEvent) -> String {
        var pieces = [event.appName]
        if event.windowTitle.isEmpty == false && event.windowTitle != event.appName {
            pieces.append(event.windowTitle)
        }
        if let url = event.url, url.isEmpty == false {
            pieces.append(url)
        }
        if event.excerpt.isEmpty == false {
            pieces.append(event.excerpt)
        }
        return pieces.joined(separator: " • ")
    }

    private func sectionPrompt(_ section: JournalSection) -> String {
        """
        Section: \(section.timeRange) • \(section.heading)
        \(section.bullets.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    private func renderMarkdown(for date: Date, sections: [JournalSection], events: [ActivityEvent]) -> String {
        guard sections.isEmpty == false else {
            return "# \(OpenbirdDateFormatting.weekdayFormatter.string(from: date)) Review\n\nNo activity captured yet."
        }

        var markdown = "# \(OpenbirdDateFormatting.weekdayFormatter.string(from: date)) Review\n\n"
        for section in sections {
            markdown += "## \(section.timeRange) — \(section.heading)\n"
            markdown += section.bullets.map { "- \($0)" }.joined(separator: "\n")
            markdown += "\n\n"
        }
        let apps = Set(events.map(\.appName)).sorted()
        if apps.isEmpty == false {
            markdown += "### Misc\n"
            markdown += "- Active apps: \(apps.joined(separator: ", "))\n"
        }
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mostFrequentString(in values: [String]) -> String? {
        values.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }
        .max(by: { $0.value < $1.value })?
        .key
    }
}
