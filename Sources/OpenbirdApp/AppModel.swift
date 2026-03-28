import AppKit
import Foundation
import OpenbirdKit

@MainActor
final class AppModel: ObservableObject {
    struct DayLoadStatus: Equatable {
        let step: Int
        let totalSteps: Int
        let title: String
        let detail: String
    }

    private static let automaticUpdateCheckInterval: TimeInterval = 60 * 60 * 12
    private static let dismissedUpdateVersionKey = "openbird.dismissedUpdateVersion"
    private static let lastUpdateCheckDateKey = "openbird.lastUpdateCheckDate"
    @Published var settings = AppSettings()
    @Published var providerConfigs: [ProviderConfig] = []
    @Published var exclusions: [ExclusionRule] = []
    @Published var installedApplications: [InstalledApplication] = []
    @Published var availableUpdate: AppUpdate?
    @Published var editingProvider = ProviderConfig.defaultOllama
    @Published var selectedDay = Date()
    @Published var todayJournal: DailyJournal?
    @Published var rawEvents: [ActivityEvent] = []
    @Published var chatThread: ChatThread?
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatInput = ""
    @Published var updateStatusMessage = ""
    @Published var providerStatusMessage = ""
    @Published private(set) var appVersion: String?
    @Published private(set) var availableProviderModels: [ProviderModelInfo] = []
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var isGeneratingTodayJournal = false
    @Published var isCheckingForUpdates = false
    @Published var isInstallingUpdate = false
    @Published var isLoadingInstalledApplications = false
    @Published var isShowingRawLogInspector = false
    @Published private(set) var shouldFocusChatComposer = false
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var dayLoadStatus: DayLoadStatus?

    let permissionsService = PermissionsService()
    private let store: OpenbirdStore
    private let installedApplicationService = InstalledApplicationService()
    private let journalGenerator: JournalGenerator
    private let retrievalService: RetrievalService
    private let chatService: ChatService
    private let retentionService: RetentionService
    private let collectorRuntime: CollectorRuntime
    private let collectorOwnerID: String
    private let updateService: UpdateService
    private let appUpdater: AppUpdater
    private let userDefaults: UserDefaults
    private var quitApplication: () -> Void = { NSApp.terminate(nil) }
    private var providerConnectionTask: Task<Void, Never>?
    private var providerSaveTask: Task<Void, Never>?
    private var updateCheckTask: Task<Void, Never>?
    private var providerConnectionRequestID = UUID()
    private var updateCheckRequestID = UUID()

    init(
        userDefaults: UserDefaults = .standard,
        updateService: UpdateService = UpdateService(),
        appUpdater: AppUpdater = AppUpdater()
    ) {
        self.userDefaults = userDefaults
        self.updateService = updateService
        self.appUpdater = appUpdater
        self.appVersion = Self.currentAppVersion()

        do {
            let store = try OpenbirdStore()
            let collectorOwnerID = CollectorRuntime.defaultOwnerID()
            let collectorOwnerName = CollectorRuntime.defaultOwnerName()
            self.store = store
            self.journalGenerator = JournalGenerator(store: store)
            self.retrievalService = RetrievalService(store: store)
            self.chatService = ChatService(store: store, retrievalService: retrievalService)
            self.retentionService = RetentionService(store: store)
            self.collectorOwnerID = collectorOwnerID
            self.collectorRuntime = CollectorRuntime(
                store: store,
                ownerID: collectorOwnerID,
                ownerName: collectorOwnerName
            )
        } catch {
            fatalError("Failed to initialize Openbird store: \(error)")
        }

        accessibilityTrusted = permissionsService.isAccessibilityTrusted
        collectorRuntime.start()
        refreshInstalledApplications()
        Task {
            await refresh()
        }
        checkForUpdatesIfNeeded()
    }

    deinit {
        providerConnectionTask?.cancel()
        providerSaveTask?.cancel()
        updateCheckTask?.cancel()
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

    var accessibilityGrantPath: String? {
        if isRunningFromAppBundle {
            return Bundle.main.bundleURL.path
        }

        return Bundle.main.executableURL?.path
    }

    var accessibilityBundleIdentifier: String? {
        Bundle.main.bundleIdentifier
    }

    var accessibilityGrantHelp: String? {
        guard accessibilityGrantPath != nil else {
            return nil
        }

        if isRunningFromAppBundle {
            let bundlePath = Bundle.main.bundleURL.path
            if bundlePath.contains("/.build/") || bundlePath.contains("/DerivedData/") {
                return "This copy is running from a local development app bundle. macOS grants Accessibility per app copy, so if you already enabled another Openbird build, add this one too. If it still looks disabled after enabling it, quit and reopen Openbird."
            }

            return "macOS grants Accessibility per app copy. If you already enabled another Openbird build, make sure it is this one. If it still looks disabled after enabling it, quit and reopen Openbird."
        }

        if let executablePath = Bundle.main.executableURL?.path,
           executablePath.contains("/DerivedData/") {
            return "This copy is running from Xcode, not from a packaged Openbird.app. macOS may list it as \(accessibilityTargetName). If it does not appear automatically, use the + button in Accessibility settings and add this exact executable. If it still looks disabled after enabling it, quit and reopen Openbird."
        }

        return "This copy is running directly from a built executable, not from a packaged Openbird.app. macOS may list it as \(accessibilityTargetName). If it does not appear automatically, use the + button in Accessibility settings and add this exact executable. If it still looks disabled after enabling it, quit and reopen Openbird."
    }

    var activeProvider: ProviderConfig? {
        ProviderSelection.resolve(configs: providerConfigs, settings: settings)
    }

    var selectedProvider: ProviderConfig? {
        providerConfigs.first { $0.id == settings.selectedProviderID }
    }

    func providerName(for id: String?) -> String? {
        guard let id else { return nil }
        return providerConfigs.first { $0.id == id }?.name
    }

    var needsOnboarding: Bool {
        accessibilityTrusted == false || activeProvider == nil
    }

    var isCollectorHeartbeatFresh: Bool {
        guard let heartbeat = settings.lastCollectorHeartbeat else {
            return false
        }
        return Date().timeIntervalSince(heartbeat) <= CollectorRuntime.leaseTimeout
    }

    var isCurrentProcessCollectorOwner: Bool {
        isCollectorHeartbeatFresh && settings.collectorOwnerID == collectorOwnerID
    }

    var isCollectorActiveElsewhere: Bool {
        isCollectorHeartbeatFresh &&
        settings.collectorOwnerID != nil &&
        settings.collectorOwnerID != collectorOwnerID
    }

    var collectorOwnerPath: String? {
        settings.collectorOwnerName
    }

    var collectorOwnerDisplayName: String? {
        guard let ownerPath = collectorOwnerPath else {
            return nil
        }
        let lastComponent = URL(fileURLWithPath: ownerPath).lastPathComponent
        return lastComponent.isEmpty ? ownerPath : lastComponent
    }

    var captureStatusLabel: String {
        if settings.capturePaused {
            return isCollectorActiveElsewhere ? "Paused Elsewhere" : "Paused"
        }
        if isCollectorActiveElsewhere {
            return "Active Elsewhere"
        }
        guard isCollectorHeartbeatFresh else {
            return "Stopped"
        }
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

    var captureStatusDetail: String {
        if isCollectorActiveElsewhere,
           let owner = collectorOwnerDisplayName {
            return "Owned by \(owner)"
        }
        return activeProvider?.name ?? "No active provider"
    }

    var availableChatModels: [ProviderModelInfo] {
        ProviderConnectionAdvisor.visibleChatModels(from: availableProviderModels, for: editingProvider.kind)
    }

    var googleDocsCaptureHint: GoogleDocsCaptureHint? {
        guard Calendar.current.isDateInToday(selectedDay) else {
            return nil
        }

        return GoogleDocsCaptureAdvisor.hint(for: rawEvents)
    }

    private var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private static func currentAppVersion() -> String? {
        guard let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              version.isEmpty == false,
              version != "0.0.0" else {
            return nil
        }

        return version
    }

    func refresh() async {
        refreshAccessibilityPermissionState()
        isBusy = true
        defer {
            isBusy = false
            dayLoadStatus = nil
        }

        do {
            let previousProviderID = editingProvider.id
            dayLoadStatus = Self.makeDayLoadStatus(
                step: 1,
                totalSteps: 5,
                title: "Loading Openbird state",
                detail: "Reading your saved settings, providers, and exclusions from the local store."
            )
            settings = try await store.loadSettings()
            providerConfigs = try await store.loadProviderConfigs()
            exclusions = try await store.loadExclusions()
            if let selectedProvider {
                editingProvider = selectedProvider
            } else if let activeProvider {
                editingProvider = activeProvider
            } else if let first = providerConfigs.first {
                editingProvider = first
            }
            if editingProvider.id != previousProviderID {
                availableProviderModels = []
            }

            let dayRange = Calendar.current.dayRange(for: selectedDay)
            dayLoadStatus = Self.makeDayLoadStatus(
                step: 2,
                totalSteps: 5,
                title: "Reading captured activity",
                detail: "Querying the local timeline database for raw events recorded on the selected day."
            )
            rawEvents = try await store.loadActivityEvents(in: dayRange, includeExcluded: true)
            dayLoadStatus = Self.makeDayLoadStatus(
                step: 3,
                totalSteps: 5,
                title: "Loading saved summary",
                detail: "Checking whether Openbird already has a journal summary cached for this day."
            )
            todayJournal = try await store.loadJournal(for: OpenbirdDateFormatting.dayString(for: selectedDay))
            dayLoadStatus = Self.makeDayLoadStatus(
                step: 4,
                totalSteps: 5,
                title: "Restoring chat thread",
                detail: "Finding the conversation that belongs to this day so follow-up questions stay anchored."
            )
            let thread = try await chatService.ensureThread(for: OpenbirdDateFormatting.dayString(for: selectedDay))
            chatThread = thread
            dayLoadStatus = Self.makeDayLoadStatus(
                step: 5,
                totalSteps: 5,
                title: "Loading prior answers",
                detail: "Pulling earlier messages into memory so the dock can answer with full context."
            )
            chatMessages = try await store.loadMessages(threadID: thread.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func makeDayLoadStatus(
        step: Int,
        totalSteps: Int,
        title: String,
        detail: String
    ) -> DayLoadStatus {
        DayLoadStatus(
            step: step,
            totalSteps: totalSteps,
            title: title,
            detail: detail
        )
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

    func checkForUpdates() {
        runUpdateCheck(force: true, showUpToDateMessage: true)
    }

    func handleAppDidBecomeActive() {
        checkForUpdatesIfNeeded()
    }

    func requestChatFocus() {
        shouldFocusChatComposer = true
    }

    func setQuitApplicationHandler(_ handler: @escaping () -> Void) {
        quitApplication = handler
    }

    func acknowledgeChatFocusRequest() {
        shouldFocusChatComposer = false
    }

    func installAvailableUpdate() {
        guard let availableUpdate else {
            return
        }
        guard isInstallingUpdate == false else {
            return
        }

        isInstallingUpdate = true
        updateStatusMessage = "Installing Openbird \(availableUpdate.version)…"

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await appUpdater.install(
                    update: availableUpdate,
                    appBundleURL: Bundle.main.bundleURL
                )
                quitApplication()
            } catch {
                isInstallingUpdate = false
                updateStatusMessage = "Openbird \(availableUpdate.version) is available."
                errorMessage = "Failed to update Openbird: \(error.localizedDescription)"
            }
        }
    }

    func refreshCollectorState() async {
        do {
            settings = try await store.loadSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
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

    func scheduleAutomaticProviderConnectionCheckIfNeeded() {
        let config = sanitizedProviderConfig(editingProvider)
        cancelPendingProviderConnectionCheck()
        clearProviderConnectionResult()

        guard shouldAutomaticallyCheckProviderConnection(for: config) else {
            return
        }

        let requestID = UUID()
        providerConnectionRequestID = requestID
        providerConnectionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(600))
            } catch {
                return
            }

            guard let self else {
                return
            }

            await self.performProviderConnectionCheck(
                using: config,
                requestID: requestID
            )
        }
    }

    func scheduleAutomaticProviderSaveIfNeeded() {
        let provider = sanitizedProviderConfig(editingProvider)
        cancelPendingProviderSave()

        providerSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }

            guard let self else {
                return
            }

            await self.persistProvider(provider, activate: false)
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

        scheduleAutomaticProviderSaveIfNeeded()
        scheduleAutomaticProviderConnectionCheckIfNeeded()
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

    private func persistProvider(_ provider: ProviderConfig, activate: Bool, statusMessage: String? = nil) async {
        do {
            var savedProvider = provider
            savedProvider.updatedAt = Date()
            savedProvider.isEnabled = true
            try await store.saveProviderConfig(savedProvider)

            var updatedSettings = try await store.loadSettings()
            updatedSettings.selectedProviderID = savedProvider.id
            if activate {
                updatedSettings.activeProviderID = savedProvider.id
            }
            try await store.saveSettings(updatedSettings)

            settings = updatedSettings
            if let index = providerConfigs.firstIndex(where: { $0.id == savedProvider.id }) {
                providerConfigs[index] = savedProvider
            } else {
                providerConfigs.append(savedProvider)
            }
            editingProvider = savedProvider
            if let statusMessage {
                providerStatusMessage = statusMessage
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        providerSaveTask = nil
    }

    private func performProviderConnectionCheck(
        using config: ProviderConfig,
        requestID: UUID
    ) async {
        guard providerConnectionRequestID == requestID else {
            return
        }

        providerStatusMessage = "Checking \(config.name)…"

        do {
            let provider = ProviderFactory.makeProvider(for: config)
            let models = try await provider.listModels()

            guard Task.isCancelled == false, providerConnectionRequestID == requestID else {
                return
            }

            availableProviderModels = models

            var updated = sanitizedProviderConfig(editingProvider)
            let chatModels = ProviderConnectionAdvisor.visibleChatModels(from: models, for: updated.kind)
            let isSelectedChatModelVisible = chatModels.contains { $0.id == updated.chatModel }
            if (ProviderConnectionAdvisor.shouldReplaceChatModel(updated.chatModel) || isSelectedChatModelVisible == false),
               let suggestedChatModel = ProviderConnectionAdvisor.suggestedChatModel(from: models, for: updated.kind) {
                updated.chatModel = suggestedChatModel
            }
            if ProviderConnectionAdvisor.shouldReplaceEmbeddingModel(updated.embeddingModel),
               let suggestedEmbeddingModel = ProviderConnectionAdvisor.suggestedEmbeddingModel(from: models) {
                updated.embeddingModel = suggestedEmbeddingModel
            }
            editingProvider = updated

            if canPersistProvider(updated, availableModels: models) {
                await persistProvider(
                    updated,
                    activate: true,
                    statusMessage: connectionSuccessMessage(models: models, kind: updated.kind, saved: true)
                )
            } else if models.isEmpty {
                providerStatusMessage = "Connection successful, but no chat models were detected."
            } else {
                providerStatusMessage = connectionSuccessMessage(models: models, kind: updated.kind, saved: false)
            }
        } catch is CancellationError {
            return
        } catch {
            guard providerConnectionRequestID == requestID else {
                return
            }
            providerStatusMessage = "Connection failed: \(error.localizedDescription)"
        }

        providerConnectionTask = nil
    }

    private func canPersistProvider(_ provider: ProviderConfig, availableModels: [ProviderModelInfo]) -> Bool {
        let chatModel = provider.chatModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard chatModel.isEmpty == false else {
            return false
        }

        let chatModels = ProviderConnectionAdvisor.visibleChatModels(from: availableModels, for: provider.kind)
        if chatModels.isEmpty == false {
            return chatModels.contains { $0.id == chatModel }
        }

        return ProviderConnectionAdvisor.shouldReplaceChatModel(chatModel) == false
    }

    private func connectionSuccessMessage(models: [ProviderModelInfo], kind: ProviderKind, saved: Bool) -> String {
        let modelCount = ProviderConnectionAdvisor.visibleChatModels(from: models, for: kind).count
        let baseMessage: String
        if modelCount == 0 {
            baseMessage = "Connection successful."
        } else {
            baseMessage = "Connection successful. Found \(modelCount) model\(modelCount == 1 ? "" : "s")."
        }

        if saved {
            return "\(baseMessage) Saved provider settings."
        }

        return baseMessage
    }

    private func shouldAutomaticallyCheckProviderConnection(for config: ProviderConfig) -> Bool {
        if config.kind.requiresAPIKey {
            return config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }

        return config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func clearProviderConnectionResult() {
        availableProviderModels = []
        providerStatusMessage = ""
    }

    private func cancelPendingProviderConnectionCheck() {
        providerConnectionTask?.cancel()
        providerConnectionTask = nil
        providerConnectionRequestID = UUID()
    }

    private func cancelPendingProviderSave() {
        providerSaveTask?.cancel()
        providerSaveTask = nil
    }

    private func checkForUpdatesIfNeeded() {
        guard appVersion != nil else {
            return
        }
        guard updateCheckTask == nil else {
            return
        }

        if let lastCheckDate = userDefaults.object(forKey: Self.lastUpdateCheckDateKey) as? Date,
           Date().timeIntervalSince(lastCheckDate) < Self.automaticUpdateCheckInterval {
            return
        }

        runUpdateCheck(force: false, showUpToDateMessage: false)
    }

    private func runUpdateCheck(force: Bool, showUpToDateMessage: Bool) {
        guard let appVersion else {
            if showUpToDateMessage {
                updateStatusMessage = "Update checks are only available in packaged Openbird releases."
            }
            return
        }
        guard isInstallingUpdate == false else {
            return
        }

        let requestID = UUID()
        updateCheckRequestID = requestID
        updateCheckTask?.cancel()
        updateCheckTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.performUpdateCheck(
                currentVersion: appVersion,
                requestID: requestID,
                force: force,
                showUpToDateMessage: showUpToDateMessage
            )
        }
    }

    private func performUpdateCheck(
        currentVersion: String,
        requestID: UUID,
        force: Bool,
        showUpToDateMessage: Bool
    ) async {
        guard updateCheckRequestID == requestID else {
            return
        }

        isCheckingForUpdates = true
        if showUpToDateMessage {
            updateStatusMessage = "Checking for updates…"
        }
        userDefaults.set(Date(), forKey: Self.lastUpdateCheckDateKey)

        defer {
            if updateCheckRequestID == requestID {
                isCheckingForUpdates = false
                updateCheckTask = nil
            }
        }

        do {
            let update = try await updateService.latestUpdate(currentVersion: currentVersion)
            guard Task.isCancelled == false, updateCheckRequestID == requestID else {
                return
            }

            if let update {
                let dismissedVersion = userDefaults.string(forKey: Self.dismissedUpdateVersionKey)
                if force || dismissedVersion != update.version {
                    availableUpdate = update
                    updateStatusMessage = "Openbird \(update.version) is available."
                } else if showUpToDateMessage {
                    updateStatusMessage = "Openbird \(update.version) is available."
                }
            } else {
                availableUpdate = nil
                if showUpToDateMessage {
                    updateStatusMessage = "Openbird is up to date."
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard updateCheckRequestID == requestID else {
                return
            }
            if showUpToDateMessage {
                errorMessage = "Failed to check for updates: \(error.localizedDescription)"
            }
        }
    }

    func installedApplication(for bundleID: String) -> InstalledApplication? {
        installedApplications.first { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    private func refreshInstalledApplications() {
        isLoadingInstalledApplications = true
        let service = installedApplicationService

        Task {
            let applications = await Task.detached(priority: .utility) {
                service.listInstalledApplications()
            }.value

            installedApplications = applications
            isLoadingInstalledApplications = false
        }
    }

    func addExclusion(kind: ExclusionKind, pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard exclusions.contains(where: {
            $0.kind == kind && $0.pattern.caseInsensitiveCompare(trimmed) == .orderedSame
        }) == false else {
            return
        }

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
        guard isGeneratingTodayJournal == false else {
            return
        }

        isGeneratingTodayJournal = true
        Task {
            defer { isGeneratingTodayJournal = false }
            do {
                let journal = try await journalGenerator.generate(
                    request: JournalGenerationRequest(
                        date: selectedDay,
                        providerID: settings.activeProviderID
                    )
                )
                todayJournal = journal
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
