import Foundation

public actor ChatService {
    private let store: OpenbirdStore
    private let retrievalService: RetrievalService

    public init(store: OpenbirdStore, retrievalService: RetrievalService) {
        self.store = store
        self.retrievalService = retrievalService
    }

    @discardableResult
    public func ensureThread(for day: String) async throws -> ChatThread {
        let threads = try await store.loadThreads()
        if let existing = threads.first(where: { $0.startDay == day }) {
            return existing
        }
        let thread = ChatThread(title: "Chat for \(day)", startDay: day)
        try await store.saveThread(thread)
        return thread
    }

    public func answer(_ query: ChatQuery) async throws -> ChatMessage {
        let settings = try await store.loadSettings()
        let providerConfigs = try await store.loadProviderConfigs()
        let providerConfig = ProviderSelection.resolve(
            configs: providerConfigs,
            settings: settings
        )
        let relevantEvents = try await retrievalService.search(
            query: query.question,
            range: query.dateRange,
            appFilters: query.appFilters,
            topK: query.topK,
            providerConfig: providerConfig
        )

        let citations = relevantEvents.map {
            Citation(
                eventID: $0.id,
                label: "\(OpenbirdDateFormatting.timeString(for: $0.startedAt)) • \($0.appName)"
            )
        }

        let answerText: String
        if let providerConfig {
            do {
                let provider = ProviderFactory.makeProvider(for: providerConfig)
                let day = OpenbirdDateFormatting.dayString(for: query.dateRange.lowerBound)
                let journal = try await store.loadJournal(for: day)
                let evidence = relevantEvents.enumerated().map { index, event in
                    """
                    [\(index + 1)] \(OpenbirdDateFormatting.timeString(for: event.startedAt)) \(event.appName)
                    Title: \(event.windowTitle)
                    URL: \(event.url ?? "n/a")
                    Text: \(event.visibleText)
                    """
                }.joined(separator: "\n\n")
                let prompt = """
                Answer the question using only the supplied evidence.
                If the evidence is weak, say so.
                Keep the answer concise.

                Journal:
                \(journal?.markdown ?? "No journal generated yet.")

                Evidence:
                \(evidence)

                Question:
                \(query.question)
                """
                let response = try await provider.chat(
                    request: ProviderChatRequest(
                        messages: [
                            ChatTurn(role: .system, content: "You are a private local activity assistant. Do not invent facts."),
                            ChatTurn(role: .user, content: prompt),
                        ]
                    )
                )
                answerText = response.content
            } catch {
                answerText = heuristicAnswer(for: query.question, events: relevantEvents)
            }
        } else {
            answerText = heuristicAnswer(for: query.question, events: relevantEvents)
        }

        let userMessage = ChatMessage(
            id: query.userMessageID,
            threadID: query.threadID,
            role: .user,
            content: query.question
        )
        let assistantMessage = ChatMessage(
            id: query.assistantMessageID,
            threadID: query.threadID,
            role: .assistant,
            content: answerText,
            citations: citations
        )
        try await store.saveMessage(userMessage)
        try await store.saveMessage(assistantMessage)
        return assistantMessage
    }

    private func heuristicAnswer(for question: String, events: [ActivityEvent]) -> String {
        guard events.isEmpty == false else {
            return "I could not find matching activity in the selected date range."
        }

        let summary = events.prefix(5).map {
            "\(OpenbirdDateFormatting.timeString(for: $0.startedAt)): \($0.appName) — \($0.displayTitle)"
        }.joined(separator: "\n")

        return """
        Based on the captured activity, here are the strongest matches for "\(question)":
        \(summary)
        """
    }
}
