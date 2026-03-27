import AppKit
import Foundation

public final class CollectorRuntime: NSObject, @unchecked Sendable {
    private let store: OpenbirdStore
    private let snapshotter = AccessibilitySnapshotter()
    private let exclusionEngine = ExclusionEngine()
    private let captureInterval: TimeInterval
    private var timer: Timer?
    private var currentEvent: ActivityEvent?
    private var currentFingerprint: String?

    public init(store: OpenbirdStore, captureInterval: TimeInterval = 6) {
        self.store = store
        self.captureInterval = captureInterval
        super.init()
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
            try? await updateCollectorStatus("stopped")
        }
    }

    @objc private func activeApplicationChanged() {
        Task { await captureNow() }
    }

    public func captureNow() async {
        do {
            var settings = try await store.loadSettings()
            if settings.capturePaused {
                currentEvent = nil
                currentFingerprint = nil
                settings.collectorStatus = "paused"
                settings.lastCollectorHeartbeat = Date()
                try await store.saveSettings(settings)
                return
            }

            guard let snapshot = snapshotter.snapshotFrontmostWindow() else {
                try await updateCollectorStatus("idle")
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

            try await updateCollectorStatus("running")
        } catch {
            try? await updateCollectorStatus("error")
        }
    }

    private func updateCollectorStatus(_ status: String) async throws {
        var settings = try await store.loadSettings()
        settings.collectorStatus = status
        settings.lastCollectorHeartbeat = Date()
        try await store.saveSettings(settings)
    }
}
