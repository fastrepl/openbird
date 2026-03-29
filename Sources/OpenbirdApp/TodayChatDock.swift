import OpenbirdKit
import SwiftUI

struct TodayChatDock: View {
    enum FocusField: Hashable {
        case composer
    }

    @ObservedObject var model: AppModel
    @Binding var isExpanded: Bool
    var focusedField: FocusState<FocusField?>.Binding

    private let contentWidth: CGFloat = 540
    private let bottomAnchor = "today-chat-bottom-anchor"
    private let transcriptHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 12) {
            if isExpanded {
                transcript
            }

            ChatComposer(
                model: model,
                focusedField: focusedField,
                expand: expandChat,
                send: sendChat
            )
        }
        .frame(maxWidth: contentWidth)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: isExpanded)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if model.displayedChatMessages.isEmpty {
                        EmptyChatState()
                            .frame(maxWidth: .infinity, minHeight: transcriptHeight, alignment: .leading)
                    } else {
                        ForEach(model.displayedChatMessages) { message in
                            ChatMessageRow(message: message)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }
            .frame(height: transcriptHeight)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: Color.black.opacity(0.18), radius: 32, y: 20)
                    .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.62),
                                Color.white.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .onAppear {
                scrollToBottom(using: proxy, animated: false)
            }
            .onChange(of: model.displayedChatMessages.last) { _, _ in
                scrollToBottom(using: proxy)
            }
        }
    }

    private func expandChat() {
        guard isExpanded == false else {
            return
        }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            isExpanded = true
        }
    }

    private func sendChat() {
        expandChat()
        model.sendChat()
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool = true) {
        guard model.displayedChatMessages.isEmpty == false else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }
}

private struct ChatMessageRow: View {
    let message: AppModel.ChatDisplayMessage
    private let messageWidth: CGFloat = 420

    private var isUser: Bool {
        message.role == .user
    }

    private var assistantStatusText: String? {
        switch message.state {
        case .thinking:
            return "Thinking…"
        case .streaming:
            return "Answering…"
        default:
            return nil
        }
    }

    var body: some View {
        HStack {
            if isUser == false {
                assistantMessage
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 72)
                userMessage
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Openbird")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let assistantStatusText {
                    Text(assistantStatusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                }
            }

            if message.state == .thinking && message.content.isEmpty {
                ThinkingStatusView()
            } else {
                Text(message.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if message.citations.isEmpty == false && message.content.isEmpty == false {
                CitationStrip(citations: message.citations)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private var userMessage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("You")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if message.state == .sending {
                    Text("Sent")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.18), in: Capsule())
                }
            }

            Text(message.content)
                .textSelection(.enabled)
        }
        .frame(maxWidth: messageWidth, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16))
        }
    }
}

private struct CitationStrip: View {
    let citations: [Citation]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(citations) { citation in
                    Text(citation.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
    }
}

private struct ThinkingStatusView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Looking through your day…")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ChatComposer: View {
    @ObservedObject var model: AppModel
    var focusedField: FocusState<TodayChatDock.FocusField?>.Binding
    let expand: () -> Void
    let send: () -> Void

    private var canSend: Bool {
        model.chatThread != nil &&
        model.isSendingChat == false &&
        model.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TextField("", text: $model.chatInput, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...6)
                .focused(focusedField, equals: .composer)
                .onSubmit(send)
                .padding(.leading, 18)
                .padding(.trailing, 64)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: Color.black.opacity(0.14), radius: 24, y: 14)
                        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.62),
                                    Color.white.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )

            if model.chatInput.isEmpty {
                HStack {
                    Text("Ask what you did, where you were working, or what was open…")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.leading, 18)
                .padding(.trailing, 64)
                .padding(.vertical, 16)
                .allowsHitTesting(false)
            }

            Button(action: send) {
                Group {
                    if model.isSendingChat {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .clipShape(Circle())
            .disabled(canSend == false)
            .padding(10)
        }
        .onChange(of: focusedField.wrappedValue) { _, newValue in
            if newValue == .composer {
                expand()
            }
        }
    }
}

private struct EmptyChatState: View {
    private let contentWidth: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask Openbird about your day")
                .font(.title2.weight(.semibold))
            Text("Questions about what you worked on, where you spent time, or what changed through the day will show up here as a focused conversation.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: contentWidth, alignment: .leading)
    }
}
