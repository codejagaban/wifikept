import SwiftUI

struct AskView: View {
    @EnvironmentObject var app: AppState
    // Observed directly so streamed tokens repaint immediately.
    @ObservedObject private var engine = AppState.shared.ask
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "Is my connection good right now?",
        "Why might my Wi-Fi feel slow?",
        "How much data have I used this week?",
        "Explain my signal numbers simply",
    ]

    var body: some View {
        Group {
            if engine.available {
                chat
            } else {
                unavailableState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chat

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if engine.messages.isEmpty {
                            emptyChat
                        } else {
                            ForEach(engine.messages) { msg in
                                bubble(msg)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(20)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: engine.messages) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            inputBar
        }
    }

    private var emptyChat: some View {
        VStack(spacing: 18) {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 40))
                .foregroundStyle(Theme.purple)
            Text("Ask about your connection")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Answers come from your live connection data — signal, speed, usage — and never leave this Mac.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        submit(s)
                    } label: {
                        Text(s)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
        .padding(.top, 70)
    }

    private func bubble(_ msg: AskEngine.Message) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 120) }
            Group {
                if msg.role == .assistant && msg.text.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Thinking…")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Text(msg.text)
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(msg.role == .user ? Theme.blue.opacity(0.28) : Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(msg.role == .user ? Theme.blue.opacity(0.35) : Theme.stroke,
                                          lineWidth: 1)
                    )
            )
            if msg.role == .assistant { Spacer(minLength: 120) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            if !engine.messages.isEmpty {
                Button {
                    engine.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Clear conversation")
                .disabled(engine.isResponding)
            }
            TextField("Ask about your Wi-Fi…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .focused($inputFocused)
                .onSubmit { submit(draft) }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            Button {
                submit(draft)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(canSend ? Theme.blue : Theme.textTertiary.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
        .background(Theme.windowBG)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty && !engine.isResponding
    }

    private func submit(_ text: String) {
        guard !engine.isResponding else { return }
        let question = text
        draft = ""
        inputFocused = true
        Task { await engine.send(question, context: app.askContext()) }
    }

    // MARK: - Unavailable

    private var unavailableState: some View {
        VStack(spacing: 16) {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 44))
                .foregroundStyle(Theme.textTertiary)
            Text("Ask needs Apple Intelligence")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(engine.unavailabilityHint ?? "")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text("The conversation runs entirely on this Mac — nothing is uploaded.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(40)
    }
}
