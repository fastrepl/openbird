import Foundation

public struct AppSettings: Codable, Hashable, Sendable {
    public var capturePaused: Bool
    public var retentionDays: Int
    public var activeProviderID: String?
    public var lastCollectorHeartbeat: Date?
    public var collectorStatus: String
    public var collectorOwnerID: String?
    public var collectorOwnerName: String?

    public init(
        capturePaused: Bool = false,
        retentionDays: Int = 14,
        activeProviderID: String? = nil,
        lastCollectorHeartbeat: Date? = nil,
        collectorStatus: String = "stopped",
        collectorOwnerID: String? = nil,
        collectorOwnerName: String? = nil
    ) {
        self.capturePaused = capturePaused
        self.retentionDays = retentionDays
        self.activeProviderID = activeProviderID
        self.lastCollectorHeartbeat = lastCollectorHeartbeat
        self.collectorStatus = collectorStatus
        self.collectorOwnerID = collectorOwnerID
        self.collectorOwnerName = collectorOwnerName
    }
}
