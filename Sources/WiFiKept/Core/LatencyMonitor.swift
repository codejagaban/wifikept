import Foundation
import Network

/// Measures round-trip latency as TCP connect time to 1.1.1.1:443.
/// No privileges needed (unlike raw ICMP) and tracks real path latency closely.
enum LatencyProbe {
    static func measure(host: String = "1.1.1.1", port: UInt16 = 443,
                        timeout: TimeInterval = 3) async -> Double? {
        await withCheckedContinuation { cont in
            let conn = NWConnection(host: NWEndpoint.Host(host),
                                    port: NWEndpoint.Port(rawValue: port)!,
                                    using: .tcp)
            let start = CFAbsoluteTimeGetCurrent()
            let lock = NSLock()
            var finished = false

            func finish(_ value: Double?) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                conn.cancel()
                cont.resume(returning: value)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish((CFAbsoluteTimeGetCurrent() - start) * 1000)
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }
        }
    }
}
