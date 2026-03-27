import Foundation

public enum ProviderFactory {
    public static func makeProvider(for config: ProviderConfig, session: URLSession = .shared) -> any LLMProvider {
        switch config.kind {
        case .ollama:
            return OllamaProvider(config: config, session: session)
        case .openAICompatible:
            return OpenAICompatibleProvider(config: config, session: session)
        }
    }
}
