import Foundation

public enum ProviderFactory {
    public static func makeProvider(for config: ProviderConfig, session: URLSession = .shared) -> any LLMProvider {
        switch config.kind {
        case .ollama:
            return OllamaProvider(config: config, session: session)
        case .openAICompatible, .openAI, .anthropic, .google, .openRouter:
            return HostedProvider(config: config, session: session)
        }
    }
}
