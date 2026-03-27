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

            HStack {
                Button("Use Ollama Preset") {
                    model.useProviderPreset(.defaultOllama)
                }
                Button("Use LM Studio Preset") {
                    model.useProviderPreset(.defaultLMStudio)
                }
            }

            Picker("Configured providers", selection: Binding(
                get: { model.editingProvider.id },
                set: { newID in
                    if let config = model.providerConfigs.first(where: { $0.id == newID }) {
                        model.editingProvider = config
                    }
                }
            )) {
                ForEach(model.providerConfigs) { config in
                    Text(config.name).tag(config.id)
                }
            }

            TextField("Name", text: $model.editingProvider.name)
            Picker("Kind", selection: $model.editingProvider.kind) {
                ForEach(ProviderKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            TextField("Base URL", text: $model.editingProvider.baseURL)
            SecureField("API Key (optional)", text: $model.editingProvider.apiKey)
            TextField("Chat model", text: $model.editingProvider.chatModel)
            TextField("Embedding model", text: $model.editingProvider.embeddingModel)

            HStack {
                Button("Check Connection") {
                    model.checkProviderConnection()
                }
                Button("Save") {
                    model.saveEditingProvider(makeActive: model.activeProvider == nil)
                }
                .buttonStyle(.borderedProminent)
                Button("Make Active") {
                    model.activateProvider(model.editingProvider)
                }
            }

            if model.providerStatusMessage.isEmpty == false {
                Text(model.providerStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
