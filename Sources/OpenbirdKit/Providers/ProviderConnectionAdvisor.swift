import Foundation

public enum ProviderConnectionAdvisor {
    public static func suggestedChatModel(from models: [ProviderModelInfo]) -> String? {
        models
            .map(\.id)
            .first(where: { isEmbeddingModel($0) == false })
            ?? models.first?.id
    }

    public static func suggestedEmbeddingModel(from models: [ProviderModelInfo]) -> String? {
        models
            .map(\.id)
            .first(where: isEmbeddingModel)
    }

    public static func shouldReplaceChatModel(_ current: String) -> Bool {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty || trimmed == "local-model"
    }

    public static func shouldReplaceEmbeddingModel(_ current: String) -> Bool {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty || trimmed == "text-embedding-model"
    }

    public static func isEmbeddingModel(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let embeddingHints = [
            "embed",
            "embedding",
            "nomic",
            "bge",
            "e5",
            "gte",
        ]
        return embeddingHints.contains { lowered.contains($0) }
    }
}
