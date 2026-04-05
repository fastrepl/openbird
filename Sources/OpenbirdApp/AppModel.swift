import AppKit
import Foundation
import OpenbirdKit
import OSLog

@MainActor
final class AppModel: ObservableObject {
    struct DayLoadStatus: Equatable {
        let step: Int
        let totalSteps: Int
        let title: String
        let detail: String
    }

    struct ChatDisplayMessage: Identifiable, Equatable {
        enum State: Equatable {
            case committed
            case sending
            case thinking
            case streaming
        }

        let id: String
        let role: ChatRole
        let content: String
        let citations: [Citation]
        let state: State
    }

    struct StatusMenuExclusionState: Equatable {
        struct Action: Equatable {
            let title: String
            let pattern: String
        }

        static let empty = Self(app: nil, domain: nil)

        let app: Action?
        let domain: Action?

        var hasActions: Bool {
            app != nil || domain != nil
        }
    }

    struct StatusMenuState: Equatable {
        let isCapturePaused: Bool
        let exclusionState: StatusMenuExclusionState
        let versionText: String?
        let updateStatusText: String?
    }

    private struct PendingAssistantReply {
        var message: ChatMessage
        var state: ChatDisplayMessage.State
    }

    private static let automaticUpdateCheckInterval: TimeInterval = 60 * 60 * 12
    private static let automaticSelectedDayRefreshInterval: TimeInterval = 5
    private static let automaticJournalGenerationDelay: Duration = .seconds(20)
    private static let dismissedUpdateVersionKey = "openbird.dismissedUpdateVersion"
    private static let lastUpdateCheckDateKey = "openbird.lastUpdateCheckDate"
    @Published var settings = AppSettings()
    @Published var providerConfigs: [ProviderConfig] = []
    @Published var exclusions: [ExclusionRule] = []
    @Published var installedApplications: [InstalledApplication] = []
    @Published var availableUpdate: AppUpdate?
    @Published var editingProvider = ProviderConfig.defaultOllama
    @Published var selectedDay: Date
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
    @Published var isUpdateRestartPending = false
    @Published var isLoadingInstalledApplications = false
    @Published var isShowingRawLogInspector = false
    @Published private(set) var isSendingChat = false
    @Published private(set) var shouldFocusChatComposer = false
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var dayLoadStatus: DayLoadStatus?

    let permissionsService = PermissionsService()
    private let store: OpenbirdStore
    private let currentActivityContextService = CurrentActivityContextService()
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
    private var initialRefreshTask: Task<Void, Never>?
    private var providerConnectionTask: Task<Void, Never>?
    private var providerSaveTask: Task<Void, Never>?
    private var updateCheckTask: Task<Void, Never>?
    private var automaticJournalGenerationTask: Task<Void, Never>?
    @Published private var pendingUserChatMessage: ChatMessage?
    @Published private var pendingAssistantReply: PendingAssistantReply?
    private var chatSendTask: Task<Void, Never>?
    private var providerConnectionRequestID = UUID()
    private var updateCheckRequestID = UUID()
    private var lastAutomaticSelectedDayRefreshAt: Date?
    private var currentDayAnchor: Date
    private var isShuttingDown = false
    private let logger = OpenbirdLog.app

    init(
        userDefaults: UserDefaults = .standard,
        updateService: UpdateService = UpdateService(),
        appUpdater: AppUpdater = AppUpdater()
    ) {
        let currentDay = Self.startOfDay(for: Date())
        self.selectedDay = currentDay
        self.currentDayAnchor = currentDay
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
            logger.notice("Initialized Openbird state")
        } catch {
            logger.critical("Failed to initialize Openbird store: \(OpenbirdLog.errorDescription(error), privacy: .public)")
            fatalError("Failed to initialize Openbird store: \(error)")
        }

        accessibilityTrusted = permissionsService.isAccessibilityTrusted
        collectorRuntime.start()
        refreshInstalledApplications()
        initialRefreshTask = Task {
            await refresh()
        }
    }

    deinit {
        initialRefreshTask?.cancel()
        chatSendTask?.cancel()
        providerConnectionTask?.cancel()
        providerSaveTask?.cancel()
        updateCheckTask?.cancel()
        automaticJournalGenerationTask?.cancel()
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

    var isCapturePaused: Bool {
        settings.isCapturePaused(sessionID: collectorOwnerID)
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
        if isCapturePaused {
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
        if isCapturePaused,
           let pauseDetail = capturePauseDetail {
            return pauseDetail
        }
        return activeProvider?.name ?? "No active provider"
    }

    var capturePauseDetail: String? {
        guard isCapturePaused else {
            return nil
        }
        if settings.capturePaused {
            return "Paused until resumed"
        }
        if settings.isCapturePausedForCurrentSession(collectorOwnerID) {
            return "Paused until next launch"
        }
        if let capturePauseUntil = settings.activeCapturePauseUntil() {
            return "Resumes at \(capturePauseUntil.formatted(date: .omitted, time: .shortened))"
        }
        return "Paused until resumed"
    }

    var menuVersionText: String? {
        appVersion.map { "Openbird \($0)" }
    }

    var menuUpdateStatusText: String? {
        Self.updateStatusText(
            appVersionAvailable: appVersion != nil,
            isInstallingUpdate: isInstallingUpdate,
            isUpdateRestartPending: isUpdateRestartPending,
            availableUpdateVersion: availableUpdate?.version,
            isCheckingForUpdates: isCheckingForUpdates,
            updateStatusMessage: updateStatusMessage
        )
    }

    var availableChatModels: [ProviderModelInfo] {
        ProviderConnectionAdvisor.visibleChatModels(from: availableProviderModels, for: editingProvider.kind)
    }

    var displayedChatMessages: [ChatDisplayMessage] {
        var messages = chatMessages.map {
            ChatDisplayMessage(
                id: $0.id,
                role: $0.role,
                content: $0.content,
                citations: $0.citations,
                state: .committed
            )
        }

        if let pendingUserChatMessage {
            messages.append(
                ChatDisplayMessage(
                    id: pendingUserChatMessage.id,
                    role: pendingUserChatMessage.role,
                    content: pendingUserChatMessage.content,
                    citations: pendingUserChatMessage.citations,
                    state: .sending
                )
            )
        }

        if let pendingAssistantReply {
            messages.append(
                ChatDisplayMessage(
                    id: pendingAssistantReply.message.id,
                    role: pendingAssistantReply.message.role,
                    content: pendingAssistantReply.message.content,
                    citations: pendingAssistantReply.message.citations,
                    state: pendingAssistantReply.state
                )
            )
        }

        return messages
    }

    var googleDocsCaptureHint: GoogleDocsCaptureHint? {
        guard Calendar.autoupdatingCurrent.isDateInToday(selectedDay) else {
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

    nonisolated static func shouldAutomaticallyCheckForUpdates(
        appVersion: String?,
        isUpdateCheckInFlight: Bool,
        availableUpdate: AppUpdate?,
        lastCheckDate: Date?,
        now: Date,
        automaticUpdateCheckInterval: TimeInterval
    ) -> Bool {
        guard appVersion != nil else {
            return false
        }
        guard isUpdateCheckInFlight == false else {
            return false
        }
        guard availableUpdate == nil else {
            return false
        }
        guard let lastCheckDate else {
            return true
        }

        return now.timeIntervalSince(lastCheckDate) >= automaticUpdateCheckInterval
    }

    nonisolated static func autoAdvancedSelectedDay(
        from selectedDay: Date,
        previousCurrentDay: Date,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        let currentDay = calendar.startOfDay(for: now)
        guard calendar.isDate(currentDay, inSameDayAs: previousCurrentDay) == false else {
            return nil
        }
        guard calendar.isDate(selectedDay, inSameDayAs: previousCurrentDay) else {
            return nil
        }
        return currentDay
    }

    nonisolated static func uncompiledActivityEvents(
        from rawEvents: [ActivityEvent],
        comparedTo journal: DailyJournal
    ) -> [ActivityEvent] {
        let compiledSourceEventIDs = Set(journal.sections.flatMap(\.sourceEventIDs))
        return rawEvents.filter { event in
            event.isExcluded == false && compiledSourceEventIDs.contains(event.id) == false
        }
    }

    nonisolated static func updateStatusText(
        appVersionAvailable: Bool,
        isInstallingUpdate: Bool,
        isUpdateRestartPending: Bool,
        availableUpdateVersion: String?,
        isCheckingForUpdates: Bool,
        updateStatusMessage: String
    ) -> String? {
        guard appVersionAvailable || isUpdateRestartPending else {
            return nil
        }
        if isUpdateRestartPending {
            return "Restart Openbird to finish update"
        }
        if isInstallingUpdate {
            return "Installing update..."
        }
        if let availableUpdateVersion {
            return "Update available - \(availableUpdateVersion)"
        }
        if isCheckingForUpdates {
            return "Checking for updates..."
        }
        if updateStatusMessage.isEmpty == false {
            return updateStatusMessage
        }
        return "No new update"
    }

    func prepareForTermination() async {
        guard isShuttingDown == false else {
            return
        }

        isShuttingDown = true
        logger.notice("Preparing app model for shutdown")
        initialRefreshTask?.cancel()
        chatSendTask?.cancel()
        providerConnectionTask?.cancel()
        providerSaveTask?.cancel()
        updateCheckTask?.cancel()
        automaticJournalGenerationTask?.cancel()
        await collectorRuntime.stopAndWait()
    }

    func refresh() async {
        guard isShuttingDown == false else {
            return
        }

        let requestedDay = selectedDay
        let requestedDayString = OpenbirdDateFormatting.dayString(for: requestedDay)
        logger.notice("Refreshing app state for \(requestedDayString, privacy: .public)")
        cancelAutomaticJournalGeneration()
        chatSendTask?.cancel()
        clearTransientChatState()
        refreshAccessibilityPermissionState()
        isBusy = true
        defer {
            isBusy = false
            dayLoadStatus = nil
        }

        do {
            let previousProviderID = editingProvider.id
            rawEvents = []
            todayJournal = nil
            chatThread = nil
            chatMessages = []
            dayLoadStatus = Self.makeDayLoadStatus(
                step: 1,
                totalSteps: 5,
                title: "Loading Openbird state",
                detail: "Reading your saved settings, providers, and exclusions from the local store."
            )
            settings = try await loadCurrentSettings()
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

            let dayRange = Calendar.autoupdatingCurrent.dayRange(for: requestedDay)
            let day = OpenbirdDateFormatting.dayString(for: requestedDay)
            dayLoadStatus = Self.makeDayLoadStatus(
                step: 2,
                totalSteps: 5,
                title: "Reading captured activity",
                detail: "Querying the local timeline database for raw events recorded on the selected day."
            )
            let loadedRawEvents = try await store.loadActivityEvents(in: dayRange, includeExcluded: true)
            await store.prepareActivityEventsInBackground(for: requestedDay)
            dayLoadStatus = Self.makeDayLoadStatus(
                step: 3,
                totalSteps: 5,
                title: "Loading saved summary",
                detail: "Checking whether Openbird already has a journal summary cached for this day."
            )
            let loadedJournal = try await store.loadJournal(for: day)
            let totalDayLoadSteps = 5

            dayLoadStatus = Self.makeDayLoadStatus(
                step: 4,
                totalSteps: totalDayLoadSteps,
                title: "Restoring chat thread",
                detail: "Finding the conversation that belongs to this day so follow-up questions stay anchored."
            )
            let thread = try await chatService.ensureThread(for: day)
            dayLoadStatus = Self.makeDayLoadStatus(
                step: 5,
                totalSteps: totalDayLoadSteps,
                title: "Loading prior answers",
                detail: "Pulling earlier messages into memory so the dock can answer with full context."
            )
            let loadedChatMessages = try await store.loadMessages(threadID: thread.id)

            guard OpenbirdDateFormatting.dayString(for: selectedDay) == day else {
                return
            }

            rawEvents = loadedRawEvents
            todayJournal = loadedJournal
            chatThread = thread
            chatMessages = loadedChatMessages
            lastAutomaticSelectedDayRefreshAt = Date()
            scheduleAutomaticJournalGenerationIfNeeded()
            logger.notice(
                "Refresh completed for \(day, privacy: .public); events=\(loadedRawEvents.count, privacy: .public) journalLoaded=\((loadedJournal != nil), privacy: .public) chatMessages=\(loadedChatMessages.count, privacy: .public)"
            )
        } catch {
            logger.error("Refresh failed for \(requestedDayString, privacy: .public): \(OpenbirdLog.errorDescription(error), privacy: .public)")
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
        handleCurrentDayChangeIfNeeded()
        refreshAccessibilityPermissionState()
        checkForUpdatesIfNeeded()
    }

    func requestChatFocus() {
        shouldFocusChatComposer = true
    }

    func startNewChat() {
        chatSendTask?.cancel()
        clearTransientChatState()

        let day = OpenbirdDateFormatting.dayString(for: selectedDay)
        logger.notice("Starting a new chat for \(day, privacy: .public)")
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let thread = try await chatService.createThread(for: day)
                guard OpenbirdDateFormatting.dayString(for: selectedDay) == day else {
                    return
                }

                chatThread = thread
                chatMessages = []
                chatInput = ""
                shouldFocusChatComposer = true
                logger.notice("Started new chat thread for \(day, privacy: .public)")
            } catch {
                logger.error("Failed to start a new chat for \(day, privacy: .public): \(OpenbirdLog.errorDescription(error), privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
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
        isUpdateRestartPending = false
        updateStatusMessage = "Installing Openbird \(availableUpdate.version)…"
        logger.notice("Installing Openbird update \(availableUpdate.version, privacy: .public)")

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await appUpdater.install(
                    update: availableUpdate,
                    appBundleURL: Bundle.main.bundleURL
                )
                isInstallingUpdate = false
                isUpdateRestartPending = true
                updateStatusMessage = "Restart Openbird to finish updating to \(availableUpdate.version)."
                quitApplication()
            } catch {
                logger.error("Failed to install Openbird update \(availableUpdate.version, privacy: .public): \(OpenbirdLog.errorDescription(error), privacy: .public)")
                isInstallingUpdate = false
                isUpdateRestartPending = false
                updateStatusMessage = "Openbird \(availableUpdate.version) is available."
                errorMessage = "Failed to update Openbird: \(error.localizedDescription)"
            }
        }
    }

    func restartToFinishUpdate() {
        guard isUpdateRestartPending else {
            return
        }

        quitApplication()
    }

    func refreshCollectorState() async {
        handleCurrentDayChangeIfNeeded()
        do {
            settings = try await loadCurrentSettings()
            await refreshSelectedDayContentIfNeeded()
        } catch {
            logger.error("Failed to refresh collector state: \(OpenbirdLog.errorDescription(error), privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func toggleCapturePaused() {
        if isCapturePaused {
            resumeCapture()
            return
        }

        persistCaptureSettings { settings in
            settings.setManualCapturePaused(true)
        }
    }

    func pauseCapture(for duration: TimeInterval) {
        let pauseUntil = Date().addingTimeInterval(duration)
        logger.notice("Pausing capture for \(Int(duration), privacy: .public) seconds")
        persistCaptureSettings { settings in
            settings.pauseCapture(until: pauseUntil)
        }
    }

    func pauseCaptureUntilNextLaunch() {
        let currentSessionID = collectorOwnerID
        logger.notice("Pausing capture until next launch")
        persistCaptureSettings { settings in
            settings.pauseCaptureForCurrentSession(currentSessionID)
        }
    }

    func resumeCapture() {
        logger.notice("Resuming capture")
        persistCaptureSettings { settings in
            settings.resumeCapture()
        }
    }

    func loadStatusMenuState() async -> StatusMenuState {
        let context = await currentActivityContextService.currentContext()
        let appAction = excludableAppAction(for: context)
        let domainAction = excludableDomainAction(for: context)

        return statusMenuState(
            exclusionState: StatusMenuExclusionState(
                app: appAction,
                domain: domainAction
            )
        )
    }

    func statusMenuState(exclusionState: StatusMenuExclusionState = .empty) -> StatusMenuState {
        StatusMenuState(
            isCapturePaused: isCapturePaused,
            exclusionState: exclusionState,
            versionText: menuVersionText,
            updateStatusText: menuUpdateStatusText
        )
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
            logger.notice(
                "Saved provider configuration kind=\(savedProvider.kind.rawValue, privacy: .public) activated=\(activate, privacy: .public)"
            )
        } catch {
            logger.error(
                "Failed to save provider configuration kind=\(provider.kind.rawValue, privacy: .public): \(OpenbirdLog.errorDescription(error), privacy: .public)"
            )
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
        logger.notice("Checking provider connection kind=\(config.kind.rawValue, privacy: .public)")

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
            logger.notice(
                "Provider connection succeeded kind=\(config.kind.rawValue, privacy: .public) models=\(models.count, privacy: .public)"
            )
        } catch is CancellationError {
            return
        } catch {
            guard providerConnectionRequestID == requestID else {
                return
            }
            providerStatusMessage = "Connection failed: \(error.localizedDescription)"
            logger.error(
                "Provider connection failed kind=\(config.kind.rawValue, privacy: .public): \(OpenbirdLog.errorDescription(error), privacy: .public)"
            )
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
        let lastCheckDate = userDefaults.object(forKey: Self.lastUpdateCheckDateKey) as? Date
        guard Self.shouldAutomaticallyCheckForUpdates(
            appVersion: appVersion,
            isUpdateCheckInFlight: updateCheckTask != nil,
            availableUpdate: availableUpdate,
            lastCheckDate: lastCheckDate,
            now: Date(),
            automaticUpdateCheckInterval: Self.automaticUpdateCheckInterval
        ) else {
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
        guard isInstallingUpdate == false, isUpdateRestartPending == false else {
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
                logger.notice("Update available: \(update.version, privacy: .public)")
            } else {
                availableUpdate = nil
                if showUpToDateMessage {
                    updateStatusMessage = "Openbird is up to date."
                }
                logger.notice("Openbird is up to date")
            }
        } catch is CancellationError {
            return
        } catch {
            guard updateCheckRequestID == requestID else {
                return
            }
            logger.error("Failed to check for updates: \(OpenbirdLog.errorDescription(error), privacy: .public)")
            if showUpToDateMessage {
                errorMessage = "Failed to check for updates: \(error.localizedDescription)"
            }
        }
    }

    func installedApplication(for bundleID: String) -> InstalledApplication? {
        installedApplications.first { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    private func excludableAppAction(for context: CurrentActivityContext?) -> StatusMenuExclusionState.Action? {
        guard let context else {
            return nil
        }
        if let currentBundleID = Bundle.main.bundleIdentifier,
           currentBundleID.caseInsensitiveCompare(context.bundleID) == .orderedSame {
            return nil
        }
        guard hasExclusion(kind: .bundleID, pattern: context.bundleID) == false else {
            return nil
        }

        return StatusMenuExclusionState.Action(
            title: "Exclude current app - \(context.appName)",
            pattern: context.bundleID
        )
    }

    private func excludableDomainAction(for context: CurrentActivityContext?) -> StatusMenuExclusionState.Action? {
        guard let domain = context?.domain,
              hasExclusion(kind: .domain, pattern: domain) == false
        else {
            return nil
        }

        return StatusMenuExclusionState.Action(
            title: "Exclude current domain - \(domain)",
            pattern: domain
        )
    }

    private func hasExclusion(kind: ExclusionKind, pattern: String) -> Bool {
        exclusions.contains {
            $0.kind == kind && $0.pattern.caseInsensitiveCompare(pattern) == .orderedSame
        }
    }

    private func loadCurrentSettings() async throws -> AppSettings {
        var settings = try await store.loadSettings()
        if settings.normalizeCapturePause(sessionID: collectorOwnerID) {
            try await store.saveSettings(settings)
        }
        return settings
    }

    private func persistCaptureSettings(_ update: @escaping (inout AppSettings) -> Void) {
        Task {
            do {
                var settings = try await loadCurrentSettings()
                update(&settings)
                try await store.saveSettings(settings)
                self.settings = settings
                logger.notice(
                    "Persisted capture settings paused=\(settings.isCapturePaused(sessionID: self.collectorOwnerID), privacy: .public)"
                )
            } catch {
                logger.error("Failed to persist capture settings: \(OpenbirdLog.errorDescription(error), privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
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
                logger.notice("Added exclusion kind=\(kind.rawValue, privacy: .public)")
                await refresh()
            } catch {
                logger.error("Failed to add exclusion kind=\(kind.rawValue, privacy: .public): \(OpenbirdLog.errorDescription(error), privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func removeExclusion(id: String) {
        Task {
            do {
                try await store.deleteExclusion(id: id)
                logger.notice("Removed exclusion")
                await refresh()
            } catch {
                logger.error("Failed to remove exclusion: \(OpenbirdLog.errorDescription(error), privacy: .public)")
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
                logger.notice("Updated retention days to \(days, privacy: .public)")
                await refresh()
            } catch {
                logger.error("Failed to update retention days: \(OpenbirdLog.errorDescription(error), privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteData(scope: DataDeletionScope) {
        Task {
            do {
                try await retentionService.delete(scope: scope)
                logger.notice("Deleted data scope=\(String(describing: scope), privacy: .public)")
                await refresh()
            } catch {
                logger.error("Failed to delete data: \(OpenbirdLog.errorDescription(error), privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func generateTodayJournal() {
        cancelAutomaticJournalGeneration()
        startJournalGeneration(for: selectedDay, isAutomatic: false)
    }

    private func startJournalGeneration(for requestedDay: Date, isAutomatic: Bool) {
        guard isGeneratingTodayJournal == false else {
            return
        }

        isGeneratingTodayJournal = true
        let requestedDayString = OpenbirdDateFormatting.dayString(for: requestedDay)
        let generationMode = isAutomatic ? "Automatically generating" : "Generating"
        logger.notice("\(generationMode, privacy: .public) journal for \(requestedDayString, privacy: .public)")
        Task {
            defer { isGeneratingTodayJournal = false }
            do {
                let journal = try await generateJournal(for: requestedDay)
                guard OpenbirdDateFormatting.dayString(for: selectedDay) == OpenbirdDateFormatting.dayString(for: requestedDay) else {
                    return
                }
                todayJournal = journal
                lastAutomaticSelectedDayRefreshAt = Date()
                scheduleAutomaticJournalGenerationIfNeeded()
                let completionMode = isAutomatic ? "Automatically generated" : "Generated"
                logger.notice("\(completionMode, privacy: .public) journal for \(requestedDayString, privacy: .public)")
            } catch is CancellationError {
                return
            } catch {
                let failureMode = isAutomatic ? "automatically generate" : "generate"
                logger.error("Failed to \(failureMode, privacy: .public) journal for \(requestedDayString, privacy: .public): \(OpenbirdLog.errorDescription(error), privacy: .public)")
                if isAutomatic == false {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func sendChat() {
        let question = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let thread = chatThread, question.isEmpty == false, isSendingChat == false else { return }
        let requestedDayRange = Calendar.autoupdatingCurrent.dayRange(for: selectedDay)

        let userMessage = ChatMessage(threadID: thread.id, role: .user, content: question)
        let assistantPlaceholder = ChatMessage(threadID: thread.id, role: .assistant, content: "")
        chatInput = ""
        pendingUserChatMessage = userMessage
        pendingAssistantReply = PendingAssistantReply(message: assistantPlaceholder, state: .thinking)
        isSendingChat = true
        logger.notice("Sending chat message length=\(question.count, privacy: .public)")

        chatSendTask?.cancel()
        chatSendTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let query = ChatQuery(
                    threadID: thread.id,
                    question: question,
                    dateRange: requestedDayRange,
                    userMessageID: userMessage.id,
                    assistantMessageID: assistantPlaceholder.id
                )
                let assistantMessage = try await chatService.answer(query)

                guard Task.isCancelled == false, chatThread?.id == thread.id else {
                    return
                }

                await streamAssistantReply(assistantMessage, threadID: thread.id)
            } catch is CancellationError {
                clearTransientChatState()
            } catch {
                if chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chatInput = question
                }
                clearTransientChatState()
                logger.error("Failed to answer chat: \(OpenbirdLog.errorDescription(error), privacy: .public)")
                errorMessage = error.localizedDescription
            }

            chatSendTask = nil
        }
    }

    func selectDay(_ day: Date) {
        let normalizedDay = Self.startOfDay(for: day)
        guard Calendar.autoupdatingCurrent.isDate(selectedDay, inSameDayAs: normalizedDay) == false else {
            return
        }

        cancelAutomaticJournalGeneration()
        selectedDay = normalizedDay
        Task {
            await refresh()
        }
    }

    func handleCurrentDayChangeIfNeeded(now: Date = Date()) {
        let calendar = Calendar.autoupdatingCurrent
        let currentDay = Self.startOfDay(for: now, calendar: calendar)
        guard calendar.isDate(currentDay, inSameDayAs: currentDayAnchor) == false else {
            return
        }

        let autoSelectedDay = Self.autoAdvancedSelectedDay(
            from: selectedDay,
            previousCurrentDay: currentDayAnchor,
            now: now,
            calendar: calendar
        )
        currentDayAnchor = currentDay

        guard let autoSelectedDay else {
            return
        }

        selectDay(autoSelectedDay)
    }

    private func generateJournal(for day: Date) async throws -> DailyJournal {
        try await journalGenerator.generate(
            request: JournalGenerationRequest(
                date: day,
                providerID: settings.activeProviderID
            )
        )
    }

    private func refreshSelectedDayContentIfNeeded(now: Date = Date()) async {
        guard isBusy == false else {
            return
        }

        guard Calendar.autoupdatingCurrent.isDate(selectedDay, inSameDayAs: now) else {
            cancelAutomaticJournalGeneration()
            return
        }

        if let lastAutomaticSelectedDayRefreshAt,
           now.timeIntervalSince(lastAutomaticSelectedDayRefreshAt) < Self.automaticSelectedDayRefreshInterval {
            return
        }

        let requestedDay = selectedDay
        let requestedDayString = OpenbirdDateFormatting.dayString(for: requestedDay)
        let dayRange = Calendar.autoupdatingCurrent.dayRange(for: requestedDay)
        lastAutomaticSelectedDayRefreshAt = now

        do {
            let loadedRawEvents = try await store.loadActivityEvents(in: dayRange, includeExcluded: true)
            let loadedJournal = try await store.loadJournal(for: requestedDayString)

            guard OpenbirdDateFormatting.dayString(for: selectedDay) == requestedDayString else {
                return
            }

            if rawEvents != loadedRawEvents {
                rawEvents = loadedRawEvents
            }
            if todayJournal != loadedJournal {
                todayJournal = loadedJournal
            }

            scheduleAutomaticJournalGenerationIfNeeded()
        } catch {
            logger.error("Failed to refresh selected day content for \(requestedDayString, privacy: .public): \(OpenbirdLog.errorDescription(error), privacy: .public)")
        }
    }

    private func scheduleAutomaticJournalGenerationIfNeeded() {
        guard isShuttingDown == false else {
            return
        }
        guard Calendar.autoupdatingCurrent.isDate(selectedDay, inSameDayAs: Date()) else {
            cancelAutomaticJournalGeneration()
            return
        }
        guard isGeneratingTodayJournal == false else {
            return
        }
        guard let journal = todayJournal else {
            cancelAutomaticJournalGeneration()
            return
        }
        guard Self.uncompiledActivityEvents(from: rawEvents, comparedTo: journal).isEmpty == false else {
            cancelAutomaticJournalGeneration()
            return
        }
        guard automaticJournalGenerationTask == nil else {
            return
        }

        let requestedDay = selectedDay
        automaticJournalGenerationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.automaticJournalGenerationDelay)
            } catch {
                return
            }

            await self?.runAutomaticJournalGenerationIfNeeded(for: requestedDay)
        }
    }

    private func runAutomaticJournalGenerationIfNeeded(for requestedDay: Date) async {
        automaticJournalGenerationTask = nil

        guard isShuttingDown == false else {
            return
        }
        guard Calendar.autoupdatingCurrent.isDate(selectedDay, inSameDayAs: requestedDay),
              Calendar.autoupdatingCurrent.isDate(requestedDay, inSameDayAs: Date()),
              let journal = todayJournal
        else {
            return
        }
        guard Self.uncompiledActivityEvents(from: rawEvents, comparedTo: journal).isEmpty == false else {
            return
        }

        startJournalGeneration(for: requestedDay, isAutomatic: true)
    }

    private func cancelAutomaticJournalGeneration() {
        automaticJournalGenerationTask?.cancel()
        automaticJournalGenerationTask = nil
    }

    private func clearTransientChatState() {
        isSendingChat = false
        pendingUserChatMessage = nil
        pendingAssistantReply = nil
    }

    nonisolated private static func startOfDay(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.startOfDay(for: date)
    }

    private func streamAssistantReply(_ message: ChatMessage, threadID: String) async {
        pendingAssistantReply = PendingAssistantReply(
            message: ChatMessage(
                id: message.id,
                threadID: message.threadID,
                role: message.role,
                content: "",
                citations: message.citations,
                createdAt: message.createdAt
            ),
            state: .streaming
        )

        let characters = Array(message.content)
        let chunkCount = min(max(characters.count / 8, 12), 48)
        let chunkSize = max(1, Int(ceil(Double(max(characters.count, 1)) / Double(chunkCount))))
        var revealedCount = 0

        while revealedCount < characters.count {
            guard Task.isCancelled == false else {
                return
            }

            revealedCount = min(revealedCount + chunkSize, characters.count)
            pendingAssistantReply?.message.content = String(characters.prefix(revealedCount))
            try? await Task.sleep(for: .milliseconds(35))
        }

        do {
            chatMessages = try await store.loadMessages(threadID: threadID)
            logger.notice("Loaded persisted chat messages for thread \(threadID, privacy: .public)")
        } catch {
            logger.error("Failed to load streamed chat messages: \(OpenbirdLog.errorDescription(error), privacy: .public)")
            errorMessage = error.localizedDescription
        }

        clearTransientChatState()
    }
}
