import Foundation

/// Cloudflare-backed speed test using the methodology real speed tests use:
/// several parallel HTTP streams, time-boxed, with the TCP slow-start ramp
/// excluded from the final number. Single-stream fixed-size transfers (the
/// obvious approach) under-read badly on fast links.
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
    /// Download figure held while the upload phase runs, so the download
    /// gauge doesn't snap back to the previous result mid-test.
    @Published private(set) var interimDown: Double?
    @Published private(set) var result: Result?

    /// Called with every finished test (AppState persists them for Trends).
    var onResult: ((Result) -> Void)?

    static let cooldown: TimeInterval = 60
    private static let resultKey = "speedtest.last"

    /// Tuning: 4 parallel streams, ~6 s each way, ignore the first second
    /// (slow-start) when computing the final figure.
    private nonisolated static let streamCount = 4
    private nonisolated static let boxSeconds: Double = 6
    private nonisolated static let rampSeconds: Double = 1

    var isRunning: Bool { phase != .idle && phase != .done }

    var cooldownRemaining: Int {
        guard let last = result?.date else { return 0 }
        let left = Self.cooldown - Date().timeIntervalSince(last)
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
        liveMbps = 0
        interimDown = nil
        let down = await measure(direction: .download)
        interimDown = down

        phase = .upload
        liveMbps = 0
        let up = await measure(direction: .upload)

        let r = Result(date: Date(), downloadMbps: down, uploadMbps: up,
                       latencyMs: latency, dnsMs: dnsMs)
        result = r
        if let data = try? JSONEncoder().encode(r) {
            UserDefaults.standard.set(data, forKey: Self.resultKey)
        }
        onResult?(r)
        phase = .done
    }

    // MARK: - Transfer measurement

    private enum Direction { case download, upload }

    private nonisolated func measure(direction: Direction) async -> Double {
        let meter = TransferMeter()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpMaximumConnectionsPerHost = Self.streamCount
        let session = URLSession(configuration: config, delegate: meter, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        // Moderate chunks, continuously refilled, instead of one huge request
        // per stream: Cloudflare rate-limits large __down sizes once you've
        // moved enough volume, and a refill keeps the pipe full either way.
        // On a rejection we step down the ladder and keep going.
        let chunkLadder = [25_000_000, 10_000_000, 5_000_000, 2_000_000, 1_000_000]
        var ladderIndex = 0
        var started = 0
        let maxStarts = 80

        func startTask() {
            guard started < maxStarts else { return }
            started += 1
            let bytes = chunkLadder[ladderIndex]
            switch direction {
            case .download:
                guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)") else { return }
                session.dataTask(with: url).resume()
            case .upload:
                guard let url = URL(string: "https://speed.cloudflare.com/__up") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                // Zeros are fine; TLS payloads aren't compressed.
                session.uploadTask(with: request, from: Data(count: bytes)).resume()
            }
        }

        for _ in 0..<Self.streamCount { startTask() }

        // Sample cumulative bytes every 100 ms until the time box closes.
        let start = CFAbsoluteTimeGetCurrent()
        var samples: [(t: Double, bytes: Int64)] = [(0, 0)]
        while true {
            try? await Task.sleep(for: .milliseconds(100))
            let now = CFAbsoluteTimeGetCurrent() - start
            let bytes = meter.totalBytes
            samples.append((now, bytes))

            // A rejected request (403/429) means the current chunk size is
            // over the limit — drop down and carry on.
            if meter.consumeRejection(), ladderIndex < chunkLadder.count - 1 {
                ladderIndex += 1
            }

            // Keep the pipe full for the whole box.
            if now < Self.boxSeconds - 0.3 {
                let active = started - meter.completedTasks
                if active < Self.streamCount {
                    for _ in 0..<(Self.streamCount - active) { startTask() }
                }
            }

            // Live gauge: throughput over the trailing second.
            if let windowStart = samples.last(where: { $0.t <= now - 1 }) ?? samples.first,
               now > windowStart.t {
                let mbps = Double(bytes - windowStart.bytes) * 8 / (now - windowStart.t) / 1_000_000
                await MainActor.run { self.liveMbps = mbps }
            }

            if now >= Self.boxSeconds { break }
            if started >= maxStarts, meter.completedTasks >= started { break }
        }

        // Final figure: steady-state window, slow-start excluded.
        guard let last = samples.last, last.bytes > 0 else { return 0 }
        let rampCutoff = min(Self.rampSeconds, last.t * 0.2)
        let rampSample = samples.first(where: { $0.t >= rampCutoff }) ?? samples[0]
        let span = last.t - rampSample.t
        guard span > 0.5 else {
            // Transfer finished almost instantly; total/elapsed is the best we have.
            return Double(last.bytes) * 8 / max(last.t, 0.05) / 1_000_000
        }
        return Double(last.bytes - rampSample.bytes) * 8 / span / 1_000_000
    }
}

/// Counts bytes across all concurrent tasks in a session, both directions.
private final class TransferMeter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var received: Int64 = 0
    private var sentPerTask: [Int: Int64] = [:]
    private var completed = 0
    private var rejected = false

    var totalBytes: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return received + sentPerTask.values.reduce(0, +)
    }

    var completedTasks: Int {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    /// Returns true once per rejection burst, then resets.
    func consumeRejection() -> Bool {
        lock.lock()
        defer { rejected = false; lock.unlock() }
        return rejected
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            lock.lock()
            rejected = true
            lock.unlock()
            completionHandler(.cancel) // don't count an error body as throughput
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        received += Int64(data.count)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        lock.lock()
        sentPerTask[task.taskIdentifier] = totalBytesSent
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        completed += 1
        lock.unlock()
    }
}
