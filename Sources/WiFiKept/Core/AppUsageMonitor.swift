import Foundation
import AppKit
import Darwin

/// Per-app network attribution, sampled from `nettop` (the system's
/// per-process network statistics tool — no privileges required).
///
/// nettop reports cumulative bytes per process; we diff successive samples
/// and aggregate the deltas by app. Helper processes are attributed to
/// their parent app by walking the executable path to the outermost
/// .app bundle ("Google Chrome Helper (Renderer)" → "Google Chrome").
final class AppUsageMonitor {
    private struct Key: Hashable {
        let pid: Int32
        let name: String
    }

    private var last: [Key: (rx: Int64, tx: Int64)] = [:]
    private var firstSample = true
    private var nameCache: [Int32: String] = [:]

    private let lock = NSLock()
    private var pending: [String: (rx: Int64, tx: Int64)] = [:]
    private var lastSampleTime: Date?
    private var currentRates: [(app: String, rxBps: Double, txBps: Double)] = []

    /// Friendly names for common system daemons that move real traffic.
    private static let daemonAliases: [String: String] = [
        "mDNSResponder": "DNS Resolver",
        "apsd": "Apple Push Notifications",
        "nsurlsessiond": "System Downloads",
        "cloudd": "iCloud Sync",
        "bird": "iCloud Drive",
        "trustd": "Certificate Trust",
        "rapportd": "Continuity",
        "netbiosd": "Windows Networking",
        "syncdefaultsd": "iCloud Preferences",
        "com.apple.Safari.SafeBrowsing.Service": "Safari Safe Browsing",
        "com.apple.WebKit.Networking": "Safari (WebKit)",
    ]

    /// Take one nettop sample and bank the per-app deltas. Call off-main.
    func sample() {
        guard let output = Self.runNettop() else { return }

        var current: [Key: (rx: Int64, tx: Int64)] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let nameField = String(parts[0])
            guard let dot = nameField.lastIndex(of: "."),
                  let pid = Int32(nameField[nameField.index(after: dot)...]),
                  let rx = Int64(parts[1]), let tx = Int64(parts[2]) else { continue }
            current[Key(pid: pid, name: String(nameField[..<dot]))] = (rx, tx)
        }

        var deltas: [String: (rx: Int64, tx: Int64)] = [:]
        for (key, cur) in current {
            let d: (rx: Int64, tx: Int64)
            if let prev = last[key] {
                // Same process as last sample: credit the growth.
                d = (max(0, cur.rx - prev.rx), max(0, cur.tx - prev.tx))
            } else if firstSample {
                // Monitor just started: baseline only, don't claim history.
                d = (0, 0)
            } else {
                // Process appeared since the last sample: its total is fresh.
                d = cur
            }
            guard d.rx > 0 || d.tx > 0 else { continue }
            let app = displayName(pid: key.pid, fallback: key.name)
            var slot = deltas[app] ?? (0, 0)
            slot.rx += d.rx
            slot.tx += d.tx
            deltas[app] = slot
        }
        last = current
        firstSample = false
        nameCache = nameCache.filter { pid, _ in current.contains { $0.key.pid == pid } }

        // Live rates over this sampling interval, for the "top talkers" view.
        let now = Date()
        let interval = max(1, lastSampleTime.map { now.timeIntervalSince($0) } ?? 10)
        lastSampleTime = now
        let rates = deltas
            .map { (app: $0.key, rxBps: Double($0.value.rx) / interval, txBps: Double($0.value.tx) / interval) }
            .sorted { $0.rxBps + $0.txBps > $1.rxBps + $1.txBps }

        lock.lock()
        currentRates = Array(rates.prefix(8))
        for (app, d) in deltas {
            var slot = pending[app] ?? (0, 0)
            slot.rx += d.rx
            slot.tx += d.tx
            pending[app] = slot
        }
        lock.unlock()
    }

    /// Most recent per-app transfer rates, busiest first.
    func topTalkers() -> [(app: String, rxBps: Double, txBps: Double)] {
        lock.lock()
        defer { lock.unlock() }
        return currentRates
    }

    /// Hand over accumulated deltas (called by the flush cycle).
    func drain() -> [String: (rx: Int64, tx: Int64)] {
        lock.lock()
        defer { pending = [:]; lock.unlock() }
        return pending
    }

    // MARK: - Helpers

    private static func runNettop() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        p.arguments = ["-P", "-L", "1", "-t", "wifi", "-t", "wired",
                       "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Full app name for a pid: outermost .app bundle name when there is
    /// one (attributing helpers to their parent app), executable name for
    /// daemons, friendly aliases for well-known system services.
    private func displayName(pid: Int32, fallback: String) -> String {
        if let cached = nameCache[pid] { return cached }

        var resolved = fallback
        var buf = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 {
            let path = String(cString: buf)
            if let appRange = path.range(of: ".app/") ?? path.range(of: ".app", options: .backwards),
               let bundleStart = path[..<appRange.lowerBound].lastIndex(of: "/") {
                // Outermost bundle: first ".app" component in the path.
                let outer = path[path.index(after: path.startIndex)...]
                if let firstApp = outer.range(of: ".app") {
                    let prefix = path[..<firstApp.lowerBound]
                    if let slash = prefix.lastIndex(of: "/") {
                        resolved = String(path[path.index(after: slash)..<firstApp.lowerBound])
                    } else {
                        resolved = String(path[bundleStart..<appRange.lowerBound])
                    }
                }
            } else if let slash = path.lastIndex(of: "/") {
                resolved = String(path[path.index(after: slash)...])
            }
        }
        resolved = Self.daemonAliases[resolved] ?? resolved
        nameCache[pid] = resolved
        return resolved
    }
}
