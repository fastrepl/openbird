import AppKit
import Foundation
import OSLog

public final class CollectorRuntime: NSObject, @unchecked Sendable {
    public static let leaseTimeout: TimeInterval = 20

    private let store: OpenbirdStore
    private let snapshotter = AccessibilitySnapshotter()
    private let browserURLResolver = BrowserURLResolver()
    private let exclusionEngine = ExclusionEngine()
    private let captureGate = CaptureGate()
    private let captureInterval: TimeInterval
    private let ownerID: String
    private let ownerName: String
    private let leaseTimeout: TimeInterval
    private let lifecycleLock = NSLock()
    private let logger = OpenbirdLog.collector
    private var timer: Timer?
    private var currentEvent: ActivityEvent?
    private var currentFingerprint: String?
    private var ownsLease = false
    private var isStopped = true
    private var lastCollectorStatus: String?

    public init(
        store: OpenbirdStore,
        captureInterval: TimeInterval = 6,
        ownerID: String = CollectorRuntime.defaultOwnerID(),
        ownerName: String = CollectorRuntime.defaultOwnerName()
    ) {
        self.store = store
        self.captureInterval = captureInterval
        self.ownerID = ownerID
        self.ownerName = ownerName
        self.leaseTimeout = max(Self.leaseTimeout, captureInterval * 3)
        super.init()
    }

    public static func defaultOwnerID() -> String {
        let executablePath = Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.processName
        return "\(ProcessInfo.processInfo.processIdentifier):\(executablePath)"
    }

    public static func defaultOwnerName() -> String {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.bundleURL.path
        }
        return Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.processName
    }

    nonisolated static func shouldSkipCapture(
        for application: FrontmostApplicationContext,
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        currentBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        if application.processIdentifier == currentProcessIdentifier {
            return true
        }

        guard let currentBundleIdentifier = currentBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              currentBundleIdentifier.isEmpty == false
        else {
            return false
        }

        return currentBundleIdentifier.caseInsensitiveCompare(application.bundleID) == .orderedSame
    }

    public func start() {
        lifecycleLock.lock()
        guard isStopped else {
            lifecycleLock.unlock()
            return
        }
        isStopped = false
        lifecycleLock.unlock()
        lastCollectorStatus = nil

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        timer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            self?.scheduleCapture()
        }
        logger.notice("Collector runtime started interval=\(Int(self.captureInterval), privacy: .public)s")
        scheduleCapture()
    }

    public func stop() {
        lifecycleLock.lock()
        isStopped = true
        lifecycleLock.unlock()
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        currentEvent = nil
        currentFingerprint = nil
        lastCollectorStatus = nil
        logger.notice("Collector runtime stopped")
    }

    public func stopAndWait() async {
        stop()
        await captureGate.waitUntilIdle()
        guard ownsLease else {
            return
        }
        do {
            try await store.releaseCollectorLease(ownerID: ownerID)
            ownsLease = false
            lastCollectorStatus = nil
            logger.notice("Collector lease released")
        } catch {
            logger.error("Failed to release collector lease: \(OpenbirdLog.errorDescription(error), privacy: .public)")
        }
    }

    @objc private func activeApplicationChanged() {
        scheduleCapture()
    }

    public func captureNow() async {
        guard shouldCapture else {
            return
        }
        await captureGate.runIfIdle {
            guard self.shouldCapture else {
                return
            }
            await performCaptureNow()
        }
    }

    private func performCaptureNow() async {
        do {
            guard shouldCapture else {
                return
            }
            let now = Date()
            let claimedLease = try await store.claimCollectorLease(
                ownerID: ownerID,
                ownerName: ownerName,
                now: now,
                timeout: leaseTimeout
            )
            guard claimedLease else {
                if ownsLease {
                    logger.notice("Collector lease lost to another runtime")
                }
                ownsLease = false
                currentEvent = nil
                currentFingerprint = nil
                lastCollectorStatus = nil
                return
            }
            ownsLease = true

            guard shouldCapture else {
                return
            }

            var settings = try await store.loadSettings()
            if settings.normalizeCapturePause(now: now, sessionID: ownerID) {
                try await store.saveSettings(settings)
            }
            if settings.isCapturePaused(now: now, sessionID: ownerID) {
                currentEvent = nil
                currentFingerprint = nil
                _ = try await persistCollectorStatus("paused", heartbeat: now)
                return
            }

            guard shouldCapture else {
                return
            }

            guard let frontmostApplication = await MainActor.run(body: { FrontmostApplicationContext.current() }) else {
                _ = try await persistCollectorStatus("idle", heartbeat: now)
                return
            }

            if Self.shouldSkipCapture(for: frontmostApplication) {
                clearCurrentCaptureState()
                _ = try await persistCollectorStatus("running", heartbeat: now)
                return
            }

            let exclusions = try await store.loadExclusions()
            if exclusionEngine.isExcluded(bundleID: frontmostApplication.bundleID, url: nil, rules: exclusions) {
                clearCurrentCaptureState()
                _ = try await persistCollectorStatus("running", heartbeat: now)
                return
            }

            guard shouldCapture else {
                return
            }

            guard var snapshotPreview = snapshotter.snapshotFrontmostWindow(
                for: frontmostApplication,
                includeVisibleText: false
            ) else {
                _ = try await persistCollectorStatus("idle", heartbeat: now)
                return
            }

            if snapshotPreview.url == nil {
                snapshotPreview.url = browserURLResolver.currentURL(
                    for: snapshotPreview.bundleId,
                    windowTitle: snapshotPreview.windowTitle
                )
            }

            if exclusionEngine.isExcluded(bundleID: snapshotPreview.bundleId, url: snapshotPreview.url, rules: exclusions) {
                clearCurrentCaptureState()
                _ = try await persistCollectorStatus("running", heartbeat: snapshotPreview.capturedAt)
                return
            }

            guard var snapshot = snapshotter.snapshotFrontmostWindow(for: frontmostApplication) else {
                _ = try await persistCollectorStatus("idle", heartbeat: now)
                return
            }

            if snapshot.url == nil {
                snapshot.url = snapshotPreview.url ?? browserURLResolver.currentURL(
                    for: snapshot.bundleId,
                    windowTitle: snapshot.windowTitle
                )
            }

            guard shouldCapture else {
                return
            }

            if currentFingerprint == snapshot.fingerprint, var currentEvent {
                currentEvent.endedAt = snapshot.capturedAt
                try await store.saveActivityEvent(currentEvent)
                self.currentEvent = currentEvent
            } else {
                let event = snapshot.asEvent(startedAt: snapshot.capturedAt, excluded: false)
                try await store.saveActivityEvent(event)
                currentEvent = event
                currentFingerprint = snapshot.fingerprint
                logger.debug(
                    "Captured new activity bundleID=\(snapshot.bundleId, privacy: .public)"
                )
            }

            _ = try await persistCollectorStatus("running", heartbeat: snapshot.capturedAt)
        } catch {
            logger.error("Collector capture failed: \(OpenbirdLog.errorDescription(error), privacy: .public)")
            if ownsLease {
                _ = try? await persistCollectorStatus("error", heartbeat: Date())
            }
        }
    }

    private var shouldCapture: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return isStopped == false
    }

    private func scheduleCapture() {
        Task { [weak self] in
            await self?.captureNow()
        }
    }

    private func clearCurrentCaptureState() {
        currentEvent = nil
        currentFingerprint = nil
    }

    private func persistCollectorStatus(_ status: String, heartbeat: Date) async throws -> Bool {
        let updated = try await store.updateCollectorStatus(ownerID: ownerID, status: status, heartbeat: heartbeat)
        if updated, lastCollectorStatus != status {
            logger.notice("Collector status changed to \(status, privacy: .public)")
            lastCollectorStatus = status
        }
        return updated
    }
}

actor CaptureGate {
    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func runIfIdle(_ operation: @Sendable () async -> Void) async {
        guard isRunning == false else { return }
        isRunning = true
        defer {
            isRunning = false
            let pendingWaiters = waiters
            waiters.removeAll()
            pendingWaiters.forEach { $0.resume() }
        }
        await operation()
    }

    func waitUntilIdle() async {
        guard isRunning else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
