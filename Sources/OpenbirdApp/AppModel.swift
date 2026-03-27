import Foundation
import OpenbirdKit

@MainActor
final class AppModel: ObservableObject {
    enum SidebarItem: String, CaseIterable, Identifiable {
        case onboarding
        case today
        case chat
        case settings

        var id: String { rawValue }
        var title: String {
            switch self {
            case .onboarding:
                return "Onboarding"
            case .today:
                return "Today"
            case .chat:
                return "Chat"
            case .settings:
                return "Settings"
            }
        }
    }

    @Published var selection: SidebarItem = .onboarding
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
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var isShowingRawLogInspector = false

    let permissionsService = PermissionsService()
    private let store: OpenbirdStore
    private let journalGenerator: JournalGenerator
    private let retrievalService: RetrievalService
    private let chatService: ChatService
    private let retentionService: RetentionService
    private let collectorController = CollectorProcessController()

    init() {
        do {
            let store = try OpenbirdStore()
            self.store = store
            self.journalGenerator = JournalGenerator(store: store)
            self.retrievalService = RetrievalService(store: store)
            self.chatService = ChatService(store: store, retrievalService: retrievalService)
            self.retentionService = RetentionService(store: store)
        } catch {
            fatalError("Failed to initialize Openbird store: \(error)")
        }

        collectorController.startIfPossible()
        Task {
            await refresh()
        }
    }

    var accessibilityTrusted: Bool {
        permissionsService.isAccessibilityTrusted
    }

    var activeProvider: ProviderConfig? {
        providerConfigs.first { $0.id == settings.activeProviderID && $0.isEnabled }
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

    func refresh() async {
        isBusy = true
        defer { isBusy = false }

        do {
            settings = try await store.loadSettings()
            providerConfigs = try await store.loadProviderConfigs()
            exclusions = try await store.loadExclusions()
            if let activeProvider {
                editingProvider = activeProvider
            } else if let first = providerConfigs.first {
                editingProvider = first
            }

            if needsOnboarding == false, selection == .onboarding {
                selection = .today
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
        _ = permissionsService.requestAccessibilityPermission()
    }

    func openAccessibilitySettings() {
        permissionsService.openAccessibilitySettings()
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

    func saveEditingProvider(makeActive: Bool = false) {
        Task {
            do {
                var provider = editingProvider
                provider.updatedAt = Date()
                provider.isEnabled = true
                try await store.saveProviderConfig(provider)

                var settings = try await store.loadSettings()
                if makeActive || settings.activeProviderID == nil {
                    settings.activeProviderID = provider.id
                    try await store.saveSettings(settings)
                }
                providerStatusMessage = "Saved provider settings."
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func activateProvider(_ provider: ProviderConfig) {
        Task {
            do {
                var settings = try await store.loadSettings()
                settings.activeProviderID = provider.id
                try await store.saveSettings(settings)
                providerStatusMessage = "Active provider set to \(provider.name)."
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func checkProviderConnection() {
        let config = editingProvider
        providerStatusMessage = "Checking \(config.name)…"
        Task {
            do {
                let provider = ProviderFactory.makeProvider(for: config)
                let healthy = try await provider.healthCheck()
                providerStatusMessage = healthy ? "Connection successful." : "Provider did not respond."
            } catch {
                providerStatusMessage = "Connection failed: \(error.localizedDescription)"
            }
        }
    }

    func useProviderPreset(_ preset: ProviderConfig) {
        editingProvider = preset
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
