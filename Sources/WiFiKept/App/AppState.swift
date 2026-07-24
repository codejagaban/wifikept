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
        let sample = sampler.sample(interface: snapshot.interfaceName)
        Task { @MainActor in
            self.snap = snapshot
            if let s = sample {
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
        guard pendingRx > 0 || pendingTx > 0 else { return }
        db.addUsage(ts: Date(), rx: Int64(pendingRx), tx: Int64(pendingTx))
        pendingRx = 0
        pendingTx = 0
        lastFlush = Date()
        usageStamp += 1
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
