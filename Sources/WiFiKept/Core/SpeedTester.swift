import Foundation

/// Cloudflare-backed speed test: ~9 MB down, 5 MB up, plus TCP latency and
/// DNS resolution timing. Mirrors what the original app describes.
@MainActor
final class SpeedTester: ObservableObject {
    enum Phase: Equatable {
        case idle
        case latency
        case download
        case upload
        case done
    }

    struct Result: Codable {
        var date: Date
        var downloadMbps: Double
        var uploadMbps: Double
        var latencyMs: Double?
        var dnsMs: Double?
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var liveMbps: Double = 0     // updates while a transfer runs
    @Published private(set) var result: Result?

    static let cooldown: TimeInterval = 60
    private static let resultKey = "speedtest.last"

    var isRunning: Bool { phase != .idle && phase != .done }

    var cooldownRemaining: Int {
        guard let last = result?.date else { return 0 }
        let left = Self.cooldown - Date().timeIntervalSince(last.addingTimeInterval(0))
        return max(0, Int(left.rounded()))
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.resultKey),
           let saved = try? JSONDecoder().decode(Result.self, from: data) {
            result = saved
        }
    }

    func run() async {
        guard !isRunning else { return }

        phase = .latency
        liveMbps = 0

        let dnsMs = await Task.detached(priority: .userInitiated) {
            NetworkInfo.dnsLookupMs(host: "speed.cloudflare.com")
        }.value

        var pings: [Double] = []
        for _ in 0..<4 {
            if let ms = await LatencyProbe.measure() { pings.append(ms) }
        }
        let latency = pings.isEmpty ? nil : pings.sorted()[pings.count / 2]

        phase = .download
        let down = await measureDownload(bytes: 9_000_000)

        phase = .upload
        let up = await measureUpload(bytes: 5_000_000)

        let r = Result(date: Date(), downloadMbps: down, uploadMbps: up,
                       latencyMs: latency, dnsMs: dnsMs)
        result = r
        if let data = try? JSONEncoder().encode(r) {
            UserDefaults.standard.set(data, forKey: Self.resultKey)
        }
        phase = .done
    }

    private nonisolated func measureDownload(bytes: Int) async -> Double {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)") else { return 0 }
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let (stream, _) = try await URLSession.shared.bytes(from: url)
            var count = 0
            var lastUpdate = start
            for try await byte in stream {
                _ = byte
                count += 1
                // Update the live gauge ~5×/sec.
                if count % 262_144 == 0 {
                    let now = CFAbsoluteTimeGetCurrent()
                    if now - lastUpdate > 0.2 {
                        lastUpdate = now
                        let mbps = Double(count) * 8 / (now - start) / 1_000_000
                        await MainActor.run { self.liveMbps = mbps }
                    }
                }
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            guard elapsed > 0 else { return 0 }
            return Double(count) * 8 / elapsed / 1_000_000
        } catch {
            return 0
        }
    }

    private nonisolated func measureUpload(bytes: Int) async -> Double {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else { return 0 }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let payload = Data(count: bytes) // zeros are fine; link doesn't compress TLS payloads
        do {
            let start = CFAbsoluteTimeGetCurrent()
            _ = try await URLSession.shared.upload(for: request, from: payload)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            guard elapsed > 0 else { return 0 }
            return Double(bytes) * 8 / elapsed / 1_000_000
        } catch {
            return 0
        }
    }
}
