import Foundation
import Testing
@testable import OpenbirdKit

struct ProviderSelectionTests {
    @Test func prefersActiveProviderWhenItIsEnabled() {
        let activeProvider = ProviderConfig(
            id: "active",
            name: "Anthropic",
            kind: .anthropic,
            baseURL: ProviderKind.anthropic.defaultBaseURL,
            apiKey: "key",
            chatModel: "claude-sonnet-4",
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerProvider = ProviderConfig(
            id: "newer",
            name: "OpenAI",
            kind: .openAI,
            baseURL: ProviderKind.openAI.defaultBaseURL,
            apiKey: "key",
            chatModel: "gpt-5.4",
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let resolved = ProviderSelection.resolve(
            configs: [activeProvider, newerProvider],
            settings: AppSettings(activeProviderID: activeProvider.id)
        )

        #expect(resolved?.id == activeProvider.id)
    }

    @Test func fallsBackToSelectedProviderWhenActiveProviderIsMissing() {
        let selectedProvider = ProviderConfig(
            id: "selected",
            name: "Anthropic",
            kind: .anthropic,
            baseURL: ProviderKind.anthropic.defaultBaseURL,
            apiKey: "key",
            chatModel: "claude-sonnet-4",
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let resolved = ProviderSelection.resolve(
            configs: [selectedProvider],
            settings: AppSettings(
                activeProviderID: "missing",
                selectedProviderID: selectedProvider.id
            )
        )

        #expect(resolved?.id == selectedProvider.id)
    }

    @Test func fallsBackToMostRecentlyUpdatedEnabledProvider() {
        let olderProvider = ProviderConfig(
            id: "older",
            name: "LM Studio",
            kind: .openAICompatible,
            baseURL: ProviderKind.openAICompatible.defaultBaseURL,
            chatModel: "local-model",
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerProvider = ProviderConfig(
            id: "newer",
            name: "OpenAI",
            kind: .openAI,
            baseURL: ProviderKind.openAI.defaultBaseURL,
            apiKey: "key",
            chatModel: "gpt-5.4",
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let disabledProvider = ProviderConfig(
            id: "disabled",
            name: "Anthropic",
            kind: .anthropic,
            baseURL: ProviderKind.anthropic.defaultBaseURL,
            apiKey: "key",
            chatModel: "claude-sonnet-4",
            isEnabled: false,
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        let resolved = ProviderSelection.resolve(
            configs: [olderProvider, newerProvider, disabledProvider],
            settings: AppSettings()
        )

        #expect(resolved?.id == newerProvider.id)
    }
}
