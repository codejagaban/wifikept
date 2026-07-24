import Foundation
import FoundationModels

/// Generates the short "Insight" paragraph on each tab using Apple's
/// on-device model. Falls back to rule-based prose when Apple Intelligence
/// isn't available. Results are cached per tab and refreshed lazily.
@MainActor
final class InsightEngine: ObservableObject {
    @Published private(set) var texts: [String: String] = [:]

    private var inFlight: Set<String> = []
    private var generatedAt: [String: Date] = [:]
    private let refreshInterval: TimeInterval = 180

    var aiAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Returns the cached insight for `key` (or `fallback` while none exists)
    /// and kicks off regeneration if the cache is stale.
    func insight(for key: String, context: String, fallback: String) -> String {
        let stale = generatedAt[key].map { Date().timeIntervalSince($0) > refreshInterval } ?? true
        if stale, aiAvailable, !inFlight.contains(key) {
            inFlight.insert(key)
            Task { await generate(key: key, context: context) }
        }
        return texts[key] ?? fallback
    }

    private func generate(key: String, context: String) async {
        defer { inFlight.remove(key) }
        do {
            let session = LanguageModelSession(instructions: """
                You are a Wi-Fi diagnostics assistant inside a macOS app. \
                Given live connection metrics, reply with ONE short insight of \
                1–2 plain sentences, like a friend who knows networking. \
                Be specific to the numbers given. No markdown, no lists, no preamble.
                """)
            let response = try await session.respond(to: context)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                texts[key] = text
                generatedAt[key] = Date()
            }
        } catch {
            // Keep whatever we had; fallback text covers the gap.
            generatedAt[key] = Date().addingTimeInterval(-refreshInterval + 30)
        }
    }
}

/// Rule-based fallback prose used before the model responds (or on Macs
/// without Apple Intelligence).
enum FallbackInsight {
    static func signal(_ s: WiFiSnapshot) -> String {
        guard s.connected else { return "Not connected to Wi-Fi right now." }
        let quality = s.rssi >= -60 ? "Strong" : s.rssi >= -70 ? "Good" : s.rssi >= -80 ? "Weak" : "Very weak"
        let snrNote = s.snr >= 25 ? "a clean channel" : s.snr >= 15 ? "moderate channel noise" : "a noisy channel"
        return "\(quality) signal at \(s.rssi) dBm with \(s.snr) dB SNR — \(snrNote)."
    }

    static func speed(_ r: SpeedTester.Result?) -> String {
        guard let r else { return "Run a speed test to measure this Wi-Fi link — about 9 MB down and 5 MB up via Cloudflare." }
        let verdict = r.downloadMbps >= 100 ? "plenty for streaming and calls"
            : r.downloadMbps >= 25 ? "fine for everyday use" : "on the slow side"
        var text = String(format: "Last test: %.0f Mbps down, %.0f Mbps up — %@.",
                          r.downloadMbps, r.uploadMbps, verdict)
        if let l = r.latencyMs, l > 60 {
            text += String(format: " Latency of %.0f ms is high.", l)
        }
        return text
    }

    static func usage(today: Int64, week: Int64, month: Int64) -> String {
        "You've moved \(Fmt.bytes(today)) today, \(Fmt.bytes(week)) this week and \(Fmt.bytes(month)) this month over Wi-Fi."
    }

    static func details(_ s: WiFiSnapshot) -> String {
        guard s.connected else { return "Connect to a network to see its details." }
        return "\(s.security) on \(s.bandLabel) with \(s.standard) — a solid modern configuration."
    }

    static func trends(rows: [TrendRow]) -> String {
        guard rows.count > 4 else { return "Trend data is still being collected — check back in a few minutes." }
        let rssis = rows.map(\.rssi)
        let avg = rssis.reduce(0, +) / rssis.count
        let firstHalf = rssis.prefix(rssis.count / 2).reduce(0, +) / max(1, rssis.count / 2)
        let secondHalf = rssis.suffix(rssis.count / 2).reduce(0, +) / max(1, rssis.count / 2)
        let drift = secondHalf - firstHalf
        let direction = drift > 3 ? "improving" : drift < -3 ? "declining" : "steady"
        return "Signal has been \(direction) over this window, averaging \(avg) dBm."
    }
}
