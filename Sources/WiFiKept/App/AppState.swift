import Foundation
import SwiftUI
import AppKit
import Network

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
    /// Most recent per-app transfer rates (busiest first), ~10 s cadence.
    @Published private(set) var liveTalkers: [(app: String, rxBps: Double, txBps: Double)] = []
    /// True on hotspots/metered links (warns before a manual speed test).
    @Published private(set) var pathIsExpensive = false
    /// True while sampling is slowed down to save battery.
    @Published private(set) var batterySaver = false

    let speed = SpeedTester()
    let insights = InsightEngine()
    let ask = AskEngine()
    let db: Database

    // Only touched from init (main) and the serial fast-timer queue.
    private nonisolated(unsafe) let wifi = WiFiMonitor()
    private nonisolated(unsafe) let sampler = ThroughputSampler()
    // Sampled on its own serial background timer.
    private nonisolated(unsafe) let appMonitor = AppUsageMonitor()
    private var appTimer: DispatchSourceTimer?
    private let pathMonitor = NWPathMonitor()
    private var fastTimer: DispatchSourceTimer?
    private var slowTimer: DispatchSourceTimer?

    // Usage accumulation between flushes.
    private var pendingRx: UInt64 = 0
    private var pendingTx: UInt64 = 0
    private var lastFlush = Date()
    // Latest absolute counters (main-actor copy) for counter_state persistence.
    private var latestCounters: [String: InterfaceCounters] = [:]
    private let bootTime = InterfaceStats.bootTime()
    // Usage totals cached at each flush so per-second UI reads cost nothing.
    private var totalsCache = UsageTotals()
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
        db.compactUsage(olderThan: Date().addingTimeInterval(-7 * 86_400))

        // Speed tests are user-initiated only; drop any schedule from older builds.
        UserDefaults.standard.removeObject(forKey: "speedtest.schedule")

        reconcileOfflineUsage()
        refreshTotalsCache()
        snap = wifi.snapshot()

        speed.onResult = { [weak self] r in
            self?.db.addSpeedTest(ts: r.date, down: r.downloadMbps, up: r.uploadMbps,
                                  latency: r.latencyMs, dns: r.dnsMs)
        }

        startTimers()
        Task { await self.measureLatency() }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.pathIsExpensive = path.isExpensive }
        }
        pathMonitor.start(queue: .global(qos: .utility))
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

        // 10 s: per-app attribution sample (spawns nettop; keep off-main).
        let apps = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        apps.schedule(deadline: .now() + 5, repeating: 10)
        apps.setEventHandler { [weak self] in
            guard let self else { return }
            self.appMonitor.sample()
            let talkers = self.appMonitor.topTalkers()
            Task { @MainActor in self.liveTalkers = talkers }
        }
        apps.resume()
        appTimer = apps
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
        checkDataBudget()
        updateSamplingProfile()

        // Compact fine-grained usage rows once a day.
        let lastCompact = UserDefaults.standard.double(forKey: "usage.lastCompact")
        if Date().timeIntervalSince1970 - lastCompact > 86_400 {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "usage.lastCompact")
            db.compactUsage(olderThan: Date().addingTimeInterval(-7 * 86_400))
        }
    }

    /// Battery-aware sampling: on battery (and with no WiFiKept UI on
    /// screen) the fast counters drop from 1 s to 5 s and the nettop
    /// per-app sampler from 10 s to 30 s. Totals stay exact — the counters
    /// are cumulative — only live readouts get coarser. Re-checked every 30 s.
    private func updateSamplingProfile() {
        let enabled = UserDefaults.standard.object(forKey: "battery.saver") as? Bool ?? true
        let uiVisible = NSApp.windows.contains { $0.isVisible && $0.frame.height > 100 }
        let wantSaver = enabled && PowerSource.onBattery && !uiVisible
        guard wantSaver != batterySaver else { return }
        batterySaver = wantSaver
        let fastInterval: Double = wantSaver ? 5 : 1
        let appInterval: Double = wantSaver ? 30 : 10
        fastTimer?.schedule(deadline: .now() + fastInterval, repeating: fastInterval)
        appTimer?.schedule(deadline: .now() + appInterval, repeating: appInterval)
    }

    /// Monthly data budget: notify once at 80% and once at 100% per month.
    private func checkDataBudget() {
        let gb = UserDefaults.standard.double(forKey: "budget.gb")
        guard gb > 0 else { return }
        guard let month = Calendar.current.dateInterval(of: .month, for: Date()) else { return }
        let t = db.usageTotal(from: month.start)
        let used = Double(t.rx + t.tx)
        let limit = gb * 1_000_000_000
        let monthKey = month.start.formatted(.iso8601.year().month())
        let notifiedKey = "budget.notified.\(monthKey)"
        let notified = UserDefaults.standard.integer(forKey: notifiedKey)
        if used >= limit, notified < 100 {
            Notifier.post(title: "Data budget reached",
                          body: "You've used \(Fmt.bytes(Int64(used))) this month — past your \(Int(gb)) GB budget.")
            UserDefaults.standard.set(100, forKey: notifiedKey)
        } else if used >= limit * 0.8, notified < 80 {
            Notifier.post(title: "80% of data budget used",
                          body: "\(Fmt.bytes(Int64(used))) of your \(Int(gb)) GB monthly budget is gone.")
            UserDefaults.standard.set(80, forKey: notifiedKey)
        }
    }

    /// Label usage rows with where the data moved.
    private var currentNetworkLabel: String {
        if snap.connected, let ssid = snap.ssid { return ssid }
        return snap.connected ? "Wi-Fi" : "Wired / Other"
    }

    /// Usage grouped by network for the selected range.
    func networkTotals(range: UsageRange, limit: Int = 6) -> [(network: String?, rx: Int64, tx: Int64)] {
        db.networkTotals(from: usageRangeStart(range), limit: limit)
    }

    private func usageRangeStart(_ range: UsageRange) -> Date? {
        let cal = Calendar.current
        let now = Date()
        switch range {
        case .day: return cal.startOfDay(for: now)
        case .week: return cal.startOfDay(for: now.addingTimeInterval(-6 * 86_400))
        case .month: return cal.startOfDay(for: now.addingTimeInterval(-29 * 86_400))
        case .year: return cal.startOfDay(for: now.addingTimeInterval(-364 * 86_400))
        case .all: return nil
        }
    }

    /// Top apps by data moved for the selected usage range.
    func topApps(range: UsageRange, limit: Int = 10) -> [(app: String, rx: Int64, tx: Int64)] {
        let cal = Calendar.current
        let now = Date()
        let from: Date
        switch range {
        case .day: from = cal.startOfDay(for: now)
        case .week: from = cal.startOfDay(for: now.addingTimeInterval(-6 * 86_400))
        case .month: from = cal.startOfDay(for: now.addingTimeInterval(-29 * 86_400))
        case .year: from = cal.startOfDay(for: now.addingTimeInterval(-364 * 86_400))
        case .all: from = .distantPast
        }
        let fromDay = from == .distantPast ? "0000-00-00" : Self.dayFormatter.string(from: from)
        return db.topApps(fromDay: fromDay, limit: limit)
    }

    func speedRows(hours: Double?) -> [SpeedRow] {
        db.speedTests(from: hours.map { Date().addingTimeInterval(-$0 * 3600) })
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

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func flushUsage() {
        if pendingRx > 0 || pendingTx > 0 {
            db.addUsage(ts: Date(), rx: Int64(pendingRx), tx: Int64(pendingTx),
                        network: currentNetworkLabel)
            pendingRx = 0
            pendingTx = 0
        }
        let appDeltas = appMonitor.drain()
        if !appDeltas.isEmpty {
            let day = Self.dayFormatter.string(from: Date())
            for (app, d) in appDeltas {
                db.addAppUsage(day: day, app: app, rx: d.rx, tx: d.tx)
            }
        }
        // Persist absolute counters so a relaunch can credit whatever moved
        // while the app was closed (same boot only — counters reset on reboot).
        let now = Int64(Date().timeIntervalSince1970)
        for (iface, c) in latestCounters {
            db.saveCounterState(iface: iface, boot: bootTime,
                                rx: Int64(bitPattern: c.rx), tx: Int64(bitPattern: c.tx), seen: now)
        }
        lastFlush = Date()
        refreshTotalsCache()
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

    /// Queried from the database only at flush time (every 30 s); the
    /// per-second menu bar and popover reads come from this cache.
    private func refreshTotalsCache() {
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
        t.since = db.firstUsageDate()
        totalsCache = t
    }

    func usageTotals() -> UsageTotals {
        // Un-flushed bytes count toward every bucket.
        var t = totalsCache
        let pr = Int64(pendingRx), pt = Int64(pendingTx)
        t.today = (t.today.rx + pr, t.today.tx + pt)
        t.week = (t.week.rx + pr, t.week.tx + pt)
        t.month = (t.month.rx + pr, t.month.tx + pt)
        t.allTime = (t.allTime.rx + pr, t.allTime.tx + pt)
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

    /// Everything the Ask tab's model gets to see, refreshed per question.
    func askContext() -> String {
        var lines: [String] = []
        let s = snap
        if s.connected {
            lines.append("Network: \(s.ssid ?? "unknown (Location permission not granted)") — RSSI \(s.rssi) dBm (\(s.qualityRating), \(s.qualityPercent)%), noise \(s.noise) dBm, SNR \(s.snr) dB.")
            lines.append("Link rate \(Int(s.txRate)) Mbps, \(s.standard) (\(s.standardDetail)), channel \(s.channel) on \(s.bandLabel) at \(s.widthMHz) MHz, security \(s.security), TX power \(s.txPower) mW.")
            lines.append("IPv4 \(s.ipv4 ?? "—"), gateway \(s.gateway ?? "—"), interface \(s.interfaceName).")
        } else {
            lines.append("Not connected to Wi-Fi right now.")
        }
        if let l = latencyMs { lines.append("Current latency: \(Fmt.ms(l)).") }
        lines.append("Live throughput: \(Fmt.bytesPerSec(rxBps)) down, \(Fmt.bytesPerSec(txBps)) up.")
        if let r = speed.result {
            lines.append(String(format: "Last speed test (%@): %.0f Mbps down, %.0f Mbps up, latency %@, DNS %@.",
                                Fmt.ago(r.date), r.downloadMbps, r.uploadMbps,
                                r.latencyMs.map { Fmt.ms($0) } ?? "n/a",
                                r.dnsMs.map { Fmt.ms($0) } ?? "n/a"))
        }
        let t = usageTotals()
        lines.append("Data usage — today \(Fmt.bytes(t.today.rx)) down / \(Fmt.bytes(t.today.tx)) up, this week \(Fmt.bytes(t.week.rx)) down / \(Fmt.bytes(t.week.tx)) up, this month \(Fmt.bytes(t.month.rx + t.month.tx)) total, all time \(Fmt.bytes(t.allTime.rx + t.allTime.tx)) total.")
        let recent = trendRows(hours: 1)
        if recent.count > 2 {
            let rssis = recent.map(\.rssi)
            lines.append("Past hour: signal averaged \(rssis.reduce(0, +) / rssis.count) dBm (min \(rssis.min() ?? 0), max \(rssis.max() ?? 0)) over \(recent.count) samples.")
        }
        return lines.joined(separator: "\n")
    }

    func trendRows(hours: Double) -> [TrendRow] {
        db.trendRows(from: Date().addingTimeInterval(-hours * 3600))
    }

    func allTrendRows() -> [TrendRow] {
        db.trendRows(from: db.firstTrendDate() ?? Date())
    }
}
