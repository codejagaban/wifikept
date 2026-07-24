import Foundation
import SwiftUI

struct UsageTotals {
    var today: (rx: Int64, tx: Int64) = (0, 0)
    var week: (rx: Int64, tx: Int64) = (0, 0)
    var month: (rx: Int64, tx: Int64) = (0, 0)
    var allTime: (rx: Int64, tx: Int64) = (0, 0)
    var since: Date?
}

struct UsageBucket: Identifiable {
    var id: Date { date }
    var date: Date
    var rx: Int64
    var tx: Int64
}

enum UsageRange: String, CaseIterable, Identifiable {
    case day = "24H"
    case week = "7D"
    case month = "30D"
    case year = "12M"
    case all = "All"
    var id: String { rawValue }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var snap = WiFiSnapshot.empty
    @Published private(set) var rxBps: Double = 0
    @Published private(set) var txBps: Double = 0
    @Published private(set) var latencyMs: Double?
    @Published private(set) var liveHistory: [(date: Date, rx: Double, tx: Double)] = []
    /// Bumped whenever a usage flush lands so views re-query the DB.
    @Published private(set) var usageStamp = 0

    let speed = SpeedTester()
    let insights = InsightEngine()
    let db: Database

    // Only touched from init (main) and the serial fast-timer queue.
    private nonisolated(unsafe) let wifi = WiFiMonitor()
    private nonisolated(unsafe) let sampler = ThroughputSampler()
    private var fastTimer: DispatchSourceTimer?
    private var slowTimer: DispatchSourceTimer?

    // Usage accumulation between flushes.
    private var pendingRx: UInt64 = 0
    private var pendingTx: UInt64 = 0
    private var lastFlush = Date()
    // Latest absolute counters (main-actor copy) for counter_state persistence.
    private var latestCounters: [String: InterfaceCounters] = [:]
    private let bootTime = InterfaceStats.bootTime()
    // Throughput averaging for trend rows.
    private var trendRxAccum: Double = 0
    private var trendTxAccum: Double = 0
    private var trendSamples = 0

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WiFiKept", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        db = Database(path: dir.appendingPathComponent("store.sqlite").path)
        db.pruneTrend(before: Date().addingTimeInterval(-90 * 86_400))

        reconcileOfflineUsage()
        snap = wifi.snapshot()
        startTimers()
        Task { await self.measureLatency() }
    }

    private func startTimers() {
        // 1 s: throughput + connection snapshot.
        let fast = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        fast.schedule(deadline: .now() + 1, repeating: 1)
        fast.setEventHandler { [weak self] in self?.fastTick() }
        fast.resume()
        fastTimer = fast

        // 30 s: trend row, latency probe, usage flush check.
        let slow = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        slow.schedule(deadline: .now() + 30, repeating: 30)
        slow.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in await self?.slowTick() }
        }
        slow.resume()
        slowTimer = slow
    }

    private nonisolated func fastTick() {
        let snapshot = wifi.snapshot()
        let sample = sampler.sample()
        Task { @MainActor in
            self.snap = snapshot
            if let s = sample {
                self.latestCounters = s.counters
                // Light smoothing so the live numbers don't jitter.
                self.rxBps = self.rxBps * 0.3 + s.rxPerSec * 0.7
                self.txBps = self.txBps * 0.3 + s.txPerSec * 0.7
                self.pendingRx += s.rxDelta
                self.pendingTx += s.txDelta
                self.trendRxAccum += s.rxPerSec
                self.trendTxAccum += s.txPerSec
                self.trendSamples += 1
                self.liveHistory.append((Date(), s.rxPerSec, s.txPerSec))
                if self.liveHistory.count > 120 { self.liveHistory.removeFirst() }
            }
        }
    }

    private func slowTick() async {
        await measureLatency()
        recordTrend()
        flushUsage()
    }

    private func measureLatency() async {
        if let ms = await LatencyProbe.measure() {
            latencyMs = ms
        }
    }

    private func recordTrend() {
        guard snap.connected else { return }
        let n = max(1, trendSamples)
        db.addTrend(TrendRow(ts: Date(), rssi: snap.rssi, noise: snap.noise,
                             txRate: snap.txRate, latency: latencyMs,
                             rxBps: trendRxAccum / Double(n),
                             txBps: trendTxAccum / Double(n),
                             channel: snap.channel))
        trendRxAccum = 0
        trendTxAccum = 0
        trendSamples = 0
    }

    func flushUsage() {
        if pendingRx > 0 || pendingTx > 0 {
            db.addUsage(ts: Date(), rx: Int64(pendingRx), tx: Int64(pendingTx))
            pendingRx = 0
            pendingTx = 0
        }
        // Persist absolute counters so a relaunch can credit whatever moved
        // while the app was closed (same boot only — counters reset on reboot).
        let now = Int64(Date().timeIntervalSince1970)
        for (iface, c) in latestCounters {
            db.saveCounterState(iface: iface, boot: bootTime,
                                rx: Int64(bitPattern: c.rx), tx: Int64(bitPattern: c.tx), seen: now)
        }
        lastFlush = Date()
        usageStamp += 1
    }

    /// On launch: interface counters kept counting while the app was closed.
    /// If we're in the same boot session and the counters only moved forward,
    /// credit the difference, spread evenly across the offline window.
    private func reconcileOfflineUsage() {
        let current = InterfaceStats.readAll()
        guard !current.isEmpty else { return }
        let stored = db.loadCounterStates()
        let now = Date()
        for (iface, cur) in current {
            guard let s = stored[iface], s.boot == bootTime else { continue }
            let curRx = Int64(bitPattern: cur.rx)
            let curTx = Int64(bitPattern: cur.tx)
            guard curRx >= s.rx, curTx >= s.tx else { continue }
            let from = Date(timeIntervalSince1970: Double(s.seen))
            guard now.timeIntervalSince(from) > 5 else { continue }
            creditGap(rx: curRx - s.rx, tx: curTx - s.tx, from: from, to: now)
        }
        let ts = Int64(now.timeIntervalSince1970)
        for (iface, c) in current {
            db.saveCounterState(iface: iface, boot: bootTime,
                                rx: Int64(bitPattern: c.rx), tx: Int64(bitPattern: c.tx), seen: ts)
        }
        latestCounters = current
    }

    /// Spread an offline delta across hourly chunks so day/week boundaries
    /// still land roughly right.
    private func creditGap(rx: Int64, tx: Int64, from: Date, to: Date) {
        guard rx > 0 || tx > 0 else { return }
        let span = to.timeIntervalSince(from)
        let chunks = max(1, min(Int(span / 3600), 24 * 7))
        let step = span / Double(chunks)
        let n = Int64(chunks)
        for i in 0..<chunks {
            let ts = from.addingTimeInterval(step * (Double(i) + 0.5))
            db.addUsage(ts: ts, rx: rx / n, tx: tx / n)
        }
    }

    // MARK: - Usage queries

    func usageTotals() -> UsageTotals {
        let cal = Calendar.current
        let now = Date()
        var t = UsageTotals()
        t.today = db.usageTotal(from: cal.startOfDay(for: now))
        if let week = cal.dateInterval(of: .weekOfYear, for: now) {
            t.week = db.usageTotal(from: week.start)
        }
        if let month = cal.dateInterval(of: .month, for: now) {
            t.month = db.usageTotal(from: month.start)
        }
        t.allTime = db.usageTotal(from: nil)
        // Un-flushed bytes count toward every bucket.
        let pr = Int64(pendingRx), pt = Int64(pendingTx)
        t.today = (t.today.rx + pr, t.today.tx + pt)
        t.week = (t.week.rx + pr, t.week.tx + pt)
        t.month = (t.month.rx + pr, t.month.tx + pt)
        t.allTime = (t.allTime.rx + pr, t.allTime.tx + pt)
        t.since = db.firstUsageDate()
        return t
    }

    func usageSeries(range: UsageRange) -> [UsageBucket] {
        let cal = Calendar.current
        let now = Date()
        let from: Date?
        let component: Calendar.Component
        switch range {
        case .day: from = now.addingTimeInterval(-86_400); component = .hour
        case .week: from = cal.startOfDay(for: now.addingTimeInterval(-6 * 86_400)); component = .day
        case .month: from = cal.startOfDay(for: now.addingTimeInterval(-29 * 86_400)); component = .day
        case .year: from = cal.date(byAdding: .month, value: -11, to: cal.dateInterval(of: .month, for: now)?.start ?? now); component = .month
        case .all: from = nil; component = .month
        }
        let rows = db.usageRows(from: from)
        var buckets: [Date: (Int64, Int64)] = [:]
        for row in rows {
            guard let start = cal.dateInterval(of: component, for: row.ts)?.start else { continue }
            let cur = buckets[start] ?? (0, 0)
            buckets[start] = (cur.0 + row.rx, cur.1 + row.tx)
        }
        return buckets.keys.sorted().map { UsageBucket(date: $0, rx: buckets[$0]!.0, tx: buckets[$0]!.1) }
    }

    func trendRows(hours: Double) -> [TrendRow] {
        db.trendRows(from: Date().addingTimeInterval(-hours * 3600))
    }

    func allTrendRows() -> [TrendRow] {
        db.trendRows(from: db.firstTrendDate() ?? Date())
    }
}
