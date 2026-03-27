import AppKit
import Foundation

public final class CollectorRuntime: NSObject, @unchecked Sendable {
    public static let leaseTimeout: TimeInterval = 20

    private let store: OpenbirdStore
    private let snapshotter = AccessibilitySnapshotter()
    private let exclusionEngine = ExclusionEngine()
    private let captureInterval: TimeInterval
    private let ownerID: String
    private let ownerName: String
    private let leaseTimeout: TimeInterval
    private var timer: Timer?
    private var currentEvent: ActivityEvent?
    private var currentFingerprint: String?
    private var ownsLease = false

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

    public func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        timer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            Task { await self?.captureNow() }
        }
        Task { await captureNow() }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        Task { [weak self] in
            guard let self else { return }
            if ownsLease {
                try? await store.releaseCollectorLease(ownerID: ownerID)
            }
        }
    }

    @objc private func activeApplicationChanged() {
        Task { await captureNow() }
    }

    public func captureNow() async {
        do {
            let now = Date()
            let claimedLease = try await store.claimCollectorLease(
                ownerID: ownerID,
                ownerName: ownerName,
                now: now,
                timeout: leaseTimeout
            )
            guard claimedLease else {
                ownsLease = false
                currentEvent = nil
                currentFingerprint = nil
                return
            }
            ownsLease = true

            let settings = try await store.loadSettings()
            if settings.capturePaused {
                currentEvent = nil
                currentFingerprint = nil
                _ = try await store.updateCollectorStatus(ownerID: ownerID, status: "paused", heartbeat: now)
                return
            }

            guard let snapshot = await MainActor.run(body: { snapshotter.snapshotFrontmostWindow() }) else {
                _ = try await store.updateCollectorStatus(ownerID: ownerID, status: "idle", heartbeat: now)
                return
            }

            let exclusions = try await store.loadExclusions()
            let excluded = exclusionEngine.isExcluded(snapshot: snapshot, rules: exclusions)
            if currentFingerprint == snapshot.fingerprint, var currentEvent {
                currentEvent.endedAt = snapshot.capturedAt
                try await store.saveActivityEvent(currentEvent)
                self.currentEvent = currentEvent
            } else {
                let event = snapshot.asEvent(startedAt: snapshot.capturedAt, excluded: excluded)
                try await store.saveActivityEvent(event)
                currentEvent = event
                currentFingerprint = snapshot.fingerprint
            }

            _ = try await store.updateCollectorStatus(ownerID: ownerID, status: "running", heartbeat: snapshot.capturedAt)
        } catch {
            if ownsLease {
                _ = try? await store.updateCollectorStatus(ownerID: ownerID, status: "error", heartbeat: Date())
            }
        }
    }
}
