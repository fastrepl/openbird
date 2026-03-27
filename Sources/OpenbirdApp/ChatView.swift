import SwiftUI

struct ChatView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(model.chatMessages) { message in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message.role == .user ? "You" : "Openbird")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(message.content)
                                .textSelection(.enabled)
                            if message.citations.isEmpty == false {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(message.citations) { citation in
                                            Text(citation.label)
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                                        }
                                    }
                                }
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(message.role == .user ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask what you did, where you were working, or what was open…", text: $model.chatInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                Button("Send") {
                    model.sendChat()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .navigationTitle("Chat")
    }
}
