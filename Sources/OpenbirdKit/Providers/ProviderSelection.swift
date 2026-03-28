import Foundation

public enum ProviderSelection {
    public static func resolve(
        configs: [ProviderConfig],
        settings: AppSettings,
        preferredID: String? = nil
    ) -> ProviderConfig? {
        let enabledConfigs = configs.filter(\.isEnabled)

        if let preferredID,
           let preferredConfig = enabledConfigs.first(where: { $0.id == preferredID }) {
            return preferredConfig
        }

        if let activeProviderID = settings.activeProviderID,
           let activeConfig = enabledConfigs.first(where: { $0.id == activeProviderID }) {
            return activeConfig
        }

        if let selectedProviderID = settings.selectedProviderID,
           let selectedConfig = enabledConfigs.first(where: { $0.id == selectedProviderID }) {
            return selectedConfig
        }

        return enabledConfigs.max(by: { $0.updatedAt < $1.updatedAt })
    }
}
