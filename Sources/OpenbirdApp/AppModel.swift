import Foundation
import OpenbirdKit

@MainActor
final class AppModel: ObservableObject {
    enum SidebarItem: String, CaseIterable, Identifiable {
        case today
        case chat
        case settings

        var id: String { rawValue }
        var title: String {
            switch self {
            case .today:
                return "Today"
            case .chat:
                return "Chat"
            case .settings:
                return "Settings"
            }
        }
    }

    @Published var selection: SidebarItem = .today
    @Published var settings = AppSettings()
    @Published var providerConfigs: [ProviderConfig] = []
    @Published var exclusions: [ExclusionRule] = []
    @Published var editingProvider = ProviderConfig.defaultOllama
    @Published var selectedDay = Date()
    @Published var todayJournal: DailyJournal?
    @Published var rawEvents: [ActivityEvent] = []
    @Published var chatThread: ChatThread?
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatInput = ""
    @Published var providerStatusMessage = ""
    @Published private(set) var availableProviderModels: [ProviderModelInfo] = []
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var isShowingRawLogInspector = false
    @Published private(set) var accessibilityTrusted = false

    let permissionsService = PermissionsService()
    private let store: OpenbirdStore
    private let journalGenerator: JournalGenerator
    private let retrievalService: RetrievalService
    private let chatService: ChatService
    private let retentionService: RetentionService
    private let collectorRuntime: CollectorRuntime

    init() {
        do {
            let store = try OpenbirdStore()
            self.store = store
            self.journalGenerator = JournalGenerator(store: store)
            self.retrievalService = RetrievalService(store: store)
            self.chatService = ChatService(store: store, retrievalService: retrievalService)
            self.retentionService = RetentionService(store: store)
            self.collectorRuntime = CollectorRuntime(store: store)
        } catch {
            fatalError("Failed to initialize Openbird store: \(error)")
        }

        accessibilityTrusted = permissionsService.isAccessibilityTrusted
        collectorRuntime.start()
        Task {
            await refresh()
        }
    }

    deinit {
        collectorRuntime.stop()
    }

    var accessibilityTargetName: String {
        if isRunningFromAppBundle,
           let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           bundleName.isEmpty == false {
            return bundleName
        }

        return ProcessInfo.processInfo.processName
    }

    var accessibilityManualGrantPath: String? {
        guard isRunningFromAppBundle == false else {
            return nil
        }

        return Bundle.main.executableURL?.path
    }

    var accessibilityManualGrantHelp: String? {
        guard accessibilityManualGrantPath != nil else {
            return nil
        }

        if let executablePath = Bundle.main.executableURL?.path,
           executablePath.contains("/DerivedData/") {
            return "This copy is running from Xcode, not from a packaged Openbird.app. macOS may list it as \(accessibilityTargetName). If it does not appear automatically, use the + button in Accessibility settings and add:"
        }

        return "This copy is running directly from a built executable, not from a packaged Openbird.app. macOS may list it as \(accessibilityTargetName). If it does not appear automatically, use the + button in Accessibility settings and add:"
    }

    var activeProvider: ProviderConfig? {
        providerConfigs.first { $0.id == settings.activeProviderID && $0.isEnabled }
    }

    func providerName(for id: String?) -> String? {
        guard let id else { return nil }
        return providerConfigs.first { $0.id == id }?.name
    }

    var needsOnboarding: Bool {
        accessibilityTrusted == false || activeProvider == nil
    }

    var captureStatusLabel: String {
        if settings.capturePaused { return "Paused" }
        switch settings.collectorStatus {
        case "running":
            return "Capturing"
        case "paused":
            return "Paused"
        case "idle":
            return "Idle"
        case "error":
            return "Collector Error"
        default:
            return "Stopped"
        }
    }

    var availableChatModels: [ProviderModelInfo] {
        let models = availableProviderModels.filter { ProviderConnectionAdvisor.isEmbeddingModel($0.id) == false }
        return models.isEmpty ? availableProviderModels : models
    }

    var availableEmbeddingModels: [ProviderModelInfo] {
        availableProviderModels.filter { ProviderConnectionAdvisor.isEmbeddingModel($0.id) }
    }

    private var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func refresh() async {
        refreshAccessibilityPermissionState()
        isBusy = true
        defer { isBusy = false }

        do {
            let previousProviderID = editingProvider.id
            settings = try await store.loadSettings()
            providerConfigs = try await store.loadProviderConfigs()
            exclusions = try await store.loadExclusions()
            if let activeProvider {
                editingProvider = activeProvider
            } else if let first = providerConfigs.first {
                editingProvider = first
            }
            if editingProvider.id != previousProviderID {
                availableProviderModels = []
            }

            let dayRange = Calendar.current.dayRange(for: selectedDay)
            rawEvents = try await store.loadActivityEvents(in: dayRange, includeExcluded: true)
            todayJournal = try await store.loadJournal(for: OpenbirdDateFormatting.dayString(for: selectedDay))
            let thread = try await chatService.ensureThread(for: OpenbirdDateFormatting.dayString(for: selectedDay))
            chatThread = thread
            chatMessages = try await store.loadMessages(threadID: thread.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestAccessibilityPermission() {
        accessibilityTrusted = permissionsService.requestAccessibilityPermission()
    }

    func openAccessibilitySettings() {
        permissionsService.openAccessibilitySettings()
    }

    func refreshAccessibilityPermissionState() {
        let isTrusted = permissionsService.isAccessibilityTrusted
        guard accessibilityTrusted != isTrusted else {
            return
        }
        accessibilityTrusted = isTrusted
    }

    func toggleCapturePaused() {
        Task {
            do {
                var settings = try await store.loadSettings()
                settings.capturePaused.toggle()
                try await store.saveSettings(settings)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func saveEditingProvider() {
        Task {
            do {
                var provider = sanitizedProviderConfig(editingProvider)
                provider.updatedAt = Date()
                provider.isEnabled = true
                try await store.saveProviderConfig(provider)

                var settings = try await store.loadSettings()
                settings.activeProviderID = provider.id
                try await store.saveSettings(settings)
                providerStatusMessage = "Saved provider settings."
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func checkProviderConnection() {
        let config = sanitizedProviderConfig(editingProvider)
        providerStatusMessage = "Checking \(config.name)…"
        availableProviderModels = []
        Task {
            do {
                let provider = ProviderFactory.makeProvider(for: config)
                let models = try await provider.listModels()
                availableProviderModels = models
                var updated = config
                if ProviderConnectionAdvisor.shouldReplaceChatModel(updated.chatModel),
                   let suggestedChatModel = ProviderConnectionAdvisor.suggestedChatModel(from: models) {
                    updated.chatModel = suggestedChatModel
                }
                if ProviderConnectionAdvisor.shouldReplaceEmbeddingModel(updated.embeddingModel),
                   let suggestedEmbeddingModel = ProviderConnectionAdvisor.suggestedEmbeddingModel(from: models) {
                    updated.embeddingModel = suggestedEmbeddingModel
                }
                editingProvider = updated

                if models.isEmpty {
                    providerStatusMessage = "Connection successful."
                } else {
                    providerStatusMessage = "Connection successful. Found \(models.count) model\(models.count == 1 ? "" : "s")."
                }
            } catch {
                providerStatusMessage = "Connection failed: \(error.localizedDescription)"
            }
        }
    }

    func selectProviderKind(_ kind: ProviderKind) {
        if editingProvider.kind == kind {
            return
        }

        if let existing = providerConfigs.first(where: { $0.kind == kind && $0.isEnabled }) {
            editingProvider = existing
        } else if let existing = providerConfigs.first(where: { $0.kind == kind }) {
            editingProvider = existing
        } else {
            editingProvider = ProviderConfig.defaultPreset(for: kind)
        }

        providerStatusMessage = ""
        availableProviderModels = []
    }

    private func sanitizedProviderConfig(_ config: ProviderConfig) -> ProviderConfig {
        var sanitized = config
        sanitized.name = sanitized.kind.defaultName
        sanitized.baseURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitized.baseURL.isEmpty {
            sanitized.baseURL = sanitized.kind.defaultBaseURL
        }
        if sanitized.kind.supportsEmbeddings == false {
            sanitized.embeddingModel = ""
        }

        return sanitized
    }

    func addExclusion(kind: ExclusionKind, pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        Task {
            do {
                try await store.saveExclusion(ExclusionRule(kind: kind, pattern: trimmed))
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func removeExclusion(id: String) {
        Task {
            do {
                try await store.deleteExclusion(id: id)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func updateRetentionDays(_ days: Int) {
        Task {
            do {
                var settings = try await store.loadSettings()
                settings.retentionDays = days
                try await store.saveSettings(settings)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteData(scope: DataDeletionScope) {
        Task {
            do {
                try await retentionService.delete(scope: scope)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func generateTodayJournal() {
        Task {
            do {
                let journal = try await journalGenerator.generate(
                    request: JournalGenerationRequest(
                        date: selectedDay,
                        providerID: settings.activeProviderID
                    )
                )
                todayJournal = journal
                selection = .today
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func sendChat() {
        let question = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let thread = chatThread, question.isEmpty == false else { return }
        chatInput = ""

        Task {
            do {
                let query = ChatQuery(
                    threadID: thread.id,
                    question: question,
                    dateRange: Calendar.current.dayRange(for: selectedDay)
                )
                _ = try await chatService.answer(query)
                chatMessages = try await store.loadMessages(threadID: thread.id)
                selection = .chat
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectDay(_ day: Date) {
        selectedDay = day
        Task {
            await refresh()
        }
    }
}
