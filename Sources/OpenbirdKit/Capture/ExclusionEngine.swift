import Foundation

public struct ExclusionEngine {
    public init() {}

    public func isExcluded(snapshot: WindowSnapshot, rules: [ExclusionRule]) -> Bool {
        for rule in rules where rule.isEnabled {
            switch rule.kind {
            case .bundleID:
                if snapshot.bundleId.caseInsensitiveCompare(rule.pattern) == .orderedSame {
                    return true
                }
            case .domain:
                guard let url = snapshot.url?.lowercased() else { continue }
                let pattern = rule.pattern.lowercased()
                if url.contains(pattern) {
                    return true
                }
            }
        }
        return false
    }
}
