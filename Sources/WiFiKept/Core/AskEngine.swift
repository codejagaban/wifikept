import Foundation
import FoundationModels

/// Backs the Ask tab: a multi-turn conversation with the on-device model,
/// grounded in a fresh snapshot of connection data on every question.
@MainActor
final class AskEngine: ObservableObject {
    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        var role: Role
        var text: String
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var isResponding = false

    private var session: LanguageModelSession?

    var available: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Friendly explanation when the model can't run.
    var unavailabilityHint: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is turned off. Enable it in System Settings → Apple Intelligence & Siri, then come back — no restart needed."
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn't support Apple Intelligence, which the Ask tab needs."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading its model. Try again in a few minutes."
        case .unavailable:
            return "Apple Intelligence isn't available right now."
        }
    }

    func send(_ question: String, context: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding, available else { return }

        messages.append(Message(role: .user, text: trimmed))
        messages.append(Message(role: .assistant, text: ""))
        let answerIndex = messages.count - 1
        isResponding = true
        defer { isResponding = false }

        if session == nil {
            session = LanguageModelSession(instructions: """
                You are the Ask tab of WiFiKept, a macOS Wi-Fi monitoring app. \
                Each question comes with a snapshot of the Mac's live connection \
                data; answer from that data, specifically and concretely, like a \
                friend who knows networking. Keep answers short — a few sentences \
                of plain text, no markdown, no lists unless asked. If a question \
                is unrelated to networking or this Mac's connection, say so \
                briefly and steer back.
                """)
        }
        guard let session else { return }

        let prompt = """
            Live connection data right now:
            \(context)

            Question: \(trimmed)
            """

        do {
            let stream = session.streamResponse(to: prompt)
            for try await partial in stream {
                messages[answerIndex].text = partial.content
            }
        } catch {
            // Context window overflow or generation failure: reset the session
            // so the next question starts fresh, and say something useful.
            self.session = nil
            if messages[answerIndex].text.isEmpty {
                messages[answerIndex].text = "I couldn't finish that answer (\(error.localizedDescription)). Ask again — I've reset the conversation."
            }
        }
    }

    func clear() {
        messages = []
        session = nil
    }
}
