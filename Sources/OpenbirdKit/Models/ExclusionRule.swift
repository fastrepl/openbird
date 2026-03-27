import Foundation

public enum ExclusionKind: String, Codable, CaseIterable, Sendable {
    case bundleID
    case domain
}

public struct ExclusionRule: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var kind: ExclusionKind
    public var pattern: String
    public var isEnabled: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        kind: ExclusionKind,
        pattern: String,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.pattern = pattern
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}
