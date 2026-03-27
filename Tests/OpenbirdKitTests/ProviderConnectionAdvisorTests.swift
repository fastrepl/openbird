import Testing
@testable import OpenbirdKit

struct ProviderConnectionAdvisorTests {
    @Test func picksChatAndEmbeddingSuggestions() {
        let models = [
            ProviderModelInfo(id: "text-embedding-nomic-embed-text-v1.5"),
            ProviderModelInfo(id: "google/gemma-3n-e4b"),
            ProviderModelInfo(id: "openai/gpt-oss-20b"),
        ]

        #expect(ProviderConnectionAdvisor.suggestedChatModel(from: models) == "google/gemma-3n-e4b")
        #expect(ProviderConnectionAdvisor.suggestedEmbeddingModel(from: models) == "text-embedding-nomic-embed-text-v1.5")
    }

    @Test func recognizesPlaceholderModelNames() {
        #expect(ProviderConnectionAdvisor.shouldReplaceChatModel("local-model"))
        #expect(ProviderConnectionAdvisor.shouldReplaceEmbeddingModel("text-embedding-model"))
        #expect(ProviderConnectionAdvisor.shouldReplaceChatModel("") == true)
        #expect(ProviderConnectionAdvisor.shouldReplaceEmbeddingModel("nomic-embed-text") == false)
    }
}
