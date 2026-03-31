import Foundation

public struct ExclusionEngine {
    public init() {}

    public func isExcluded(snapshot: WindowSnapshot, rules: [ExclusionRule]) -> Bool {
        isExcluded(bundleID: snapshot.bundleId, url: snapshot.url, rules: rules)
    }

    public func isExcluded(bundleID: String, url: String?, rules: [ExclusionRule]) -> Bool {
        let snapshotDomain = normalizedDomain(from: url)

        for rule in rules where rule.isEnabled {
            switch rule.kind {
            case .bundleID:
                if bundleID.caseInsensitiveCompare(rule.pattern) == .orderedSame {
                    return true
                }
            case .domain:
                guard let snapshotDomain,
                      let excludedDomain = normalizedDomain(from: rule.pattern)
                else {
                    continue
                }

                if snapshotDomain == excludedDomain || snapshotDomain.hasSuffix(".\(excludedDomain)") {
                    return true
                }
            }
        }
        return false
    }

    private func normalizedDomain(from value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false
        else {
            return nil
        }

        let candidates = value.contains("://") ? [value] : [value, "https://\(value)"]
        for candidate in candidates {
            if let host = URLComponents(string: candidate)?.host?.lowercased(),
               host.isEmpty == false {
                return host
            }
        }

        return nil
    }
}
