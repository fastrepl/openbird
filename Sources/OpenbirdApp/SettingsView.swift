import SwiftUI
import OpenbirdKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var newExclusionPattern = ""
    @State private var exclusionKind: ExclusionKind = .bundleID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                providerSection
                captureSection
                exclusionSection
                deleteSection
            }
            .padding(28)
        }
        .navigationTitle("Settings")
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Providers")
                .font(.title3.bold())

            Picker("Provider", selection: Binding(
                get: { model.editingProvider.kind },
                set: { model.selectProviderKind($0) }
            )) {
                ForEach(ProviderKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .frame(maxWidth: 280)

            if let providerDescription {
                Text(providerDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.editingProvider.kind.showsBaseURLField {
                TextField("Endpoint", text: $model.editingProvider.baseURL)
            }
            if model.editingProvider.kind.showsAPIKeyField {
                TextField(model.editingProvider.kind.requiresAPIKey ? "API key" : "API key (optional)", text: $model.editingProvider.apiKey)
            }
            TextField("Chat model", text: $model.editingProvider.chatModel)
            if model.editingProvider.kind.supportsEmbeddings {
                TextField("Embedding model (optional)", text: $model.editingProvider.embeddingModel)
            }

            HStack {
                Button("Check Connection") {
                    model.checkProviderConnection()
                }
                Button("Save") {
                    model.saveEditingProvider()
                }
                .buttonStyle(.borderedProminent)
            }

            if model.providerStatusMessage.isEmpty == false {
                Text(model.providerStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var providerDescription: String? {
        switch model.editingProvider.kind {
        case .ollama:
            return "Runs fully local. Default endpoint is 127.0.0.1:11434."
        case .openAICompatible:
            return "Use this for LM Studio, vLLM, LocalAI, or any OpenAI-compatible endpoint."
        case .openAI:
            return "Uses your OpenAI API key with the standard OpenAI API."
        case .anthropic:
            return "Uses Claude for journal generation and chat. Embeddings stay on local search."
        case .google:
            return "Uses a Gemini API key from Google AI Studio."
        case .openRouter:
            return "Uses one OpenRouter key to access many hosted models."
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capture")
                .font(.title3.bold())
            Toggle("Pause capture", isOn: Binding(
                get: { model.settings.capturePaused },
                set: { _ in model.toggleCapturePaused() }
            ))
            Stepper("Retention days: \(model.settings.retentionDays)", value: Binding(
                get: { model.settings.retentionDays },
                set: { model.updateRetentionDays($0) }
            ), in: 1...90)
        }
    }

    private var exclusionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exclusions")
                .font(.title3.bold())
            HStack {
                Picker("Type", selection: $exclusionKind) {
                    Text("Bundle ID").tag(ExclusionKind.bundleID)
                    Text("Domain").tag(ExclusionKind.domain)
                }
                .frame(width: 160)
                TextField(exclusionKind == .bundleID ? "com.example.App" : "example.com", text: $newExclusionPattern)
                Button("Add") {
                    model.addExclusion(kind: exclusionKind, pattern: newExclusionPattern)
                    newExclusionPattern = ""
                }
            }

            ForEach(model.exclusions) { exclusion in
                HStack {
                    VStack(alignment: .leading) {
                        Text(exclusion.pattern)
                        Text(exclusion.kind == .bundleID ? "Bundle ID" : "Domain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove") {
                        model.removeExclusion(id: exclusion.id)
                    }
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete data")
                .font(.title3.bold())
            HStack {
                Button("Delete last hour") { model.deleteData(scope: .lastHour) }
                Button("Delete last day") { model.deleteData(scope: .lastDay) }
                Button("Delete all") { model.deleteData(scope: .all) }
            }
        }
    }
}
