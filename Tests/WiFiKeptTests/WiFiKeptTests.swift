import XCTest
@testable import WiFiKept

// MARK: - Signal quality

final class SignalQualityTests: XCTestCase {
    func testPercentAnchors() {
        XCTAssertEqual(SignalQuality.percent(rssi: -50), 100)
        XCTAssertEqual(SignalQuality.percent(rssi: -40), 100)   // clamped high
        XCTAssertEqual(SignalQuality.percent(rssi: -60), 85)
        XCTAssertEqual(SignalQuality.percent(rssi: -70), 65)
        XCTAssertEqual(SignalQuality.percent(rssi: -80), 40)
        XCTAssertEqual(SignalQuality.percent(rssi: -95), 0)
        XCTAssertEqual(SignalQuality.percent(rssi: -120), 0)    // clamped low
    }

    func testPercentIsMonotonic() {
        var previous = Int.max
        for rssi in stride(from: -30, through: -110, by: -1) {
            let pct = SignalQuality.percent(rssi: rssi)
            XCTAssertLessThanOrEqual(pct, previous, "percent must not increase as RSSI weakens (rssi \(rssi))")
            XCTAssertTrue((0...100).contains(pct))
            previous = pct
        }
    }

    func testRatingBoundaries() {
        XCTAssertEqual(SignalQuality.rating(rssi: -60), "Excellent")
        XCTAssertEqual(SignalQuality.rating(rssi: -61), "Good")
        XCTAssertEqual(SignalQuality.rating(rssi: -70), "Good")
        XCTAssertEqual(SignalQuality.rating(rssi: -71), "Fair")
        XCTAssertEqual(SignalQuality.rating(rssi: -80), "Fair")
        XCTAssertEqual(SignalQuality.rating(rssi: -81), "Poor")
    }
}

// MARK: - Update version comparison

final class VersionCompareTests: XCTestCase {
    @MainActor
    func testIsNewer() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.2", than: "1.0.1"))
        XCTAssertTrue(UpdateChecker.isNewer("1.1.0", than: "1.0.9"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1", than: "1.0"))   // longer wins on equal prefix
        XCTAssertFalse(UpdateChecker.isNewer("1.0.1", than: "1.0.1"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.0.1"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.0"))  // equal
        XCTAssertFalse(UpdateChecker.isNewer("0.9.9", than: "1.0"))
    }
}

// MARK: - Formatters

final class FormatterTests: XCTestCase {
    func testBitsPerSec() {
        XCTAssertEqual(Fmt.bitsPerSec(500), "500 bps")
        XCTAssertEqual(Fmt.bitsPerSec(12_000), "12 Kbps")
        XCTAssertEqual(Fmt.bitsPerSec(1_500_000), "1.5 Mbps")
        XCTAssertEqual(Fmt.bitsPerSec(153_000_000), "153 Mbps")
        XCTAssertEqual(Fmt.bitsPerSec(1_250_000_000), "1.25 Gbps")
    }

    func testBytesPerSec() {
        XCTAssertEqual(Fmt.bytesPerSec(487), "487 B/s")
        XCTAssertEqual(Fmt.bytesPerSec(2048), "2 KB/s")
        XCTAssertEqual(Fmt.bytesPerSec(1_572_864), "1.5 MB/s")
        XCTAssertEqual(Fmt.bytesPerSec(209_715_200), "200 MB/s")
    }

    func testMs() {
        XCTAssertEqual(Fmt.ms(6.83), "6.8 ms")
        XCTAssertEqual(Fmt.ms(54.2), "54 ms")
    }
}

// MARK: - Database

final class DatabaseTests: XCTestCase {
    private var db: Database!
    private var path: String!

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "wifikept-test-\(UUID().uuidString).sqlite"
        db = Database(path: path)
    }

    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(atPath: path)
        super.tearDown()
    }

    func testUsageRoundTripAndTotals() {
        let now = Date()
        db.addUsage(ts: now.addingTimeInterval(-100), rx: 1000, tx: 500, network: "Home")
        db.addUsage(ts: now.addingTimeInterval(-50), rx: 2000, tx: 700, network: "Home")
        // Same-timestamp conflict accumulates rather than replacing.
        db.addUsage(ts: now.addingTimeInterval(-50), rx: 10, tx: 20, network: "Home")

        let total = db.usageTotal(from: now.addingTimeInterval(-3600))
        XCTAssertEqual(total.rx, 3010)
        XCTAssertEqual(total.tx, 1220)

        // Range filter excludes older rows.
        let recent = db.usageTotal(from: now.addingTimeInterval(-60))
        XCTAssertEqual(recent.rx, 2010)

        // Zero-byte rows are not stored.
        db.addUsage(ts: now, rx: 0, tx: 0, network: "Home")
        XCTAssertEqual(db.usageRows(from: nil).count, 2)
    }

    func testNetworkTotalsGroupsAndOrders() {
        let now = Date()
        db.addUsage(ts: now.addingTimeInterval(-10), rx: 100, tx: 0, network: "Small")
        db.addUsage(ts: now.addingTimeInterval(-20), rx: 5000, tx: 0, network: "Big")
        db.addUsage(ts: now.addingTimeInterval(-30), rx: 300, tx: 0, network: nil)

        let totals = db.networkTotals(from: nil, limit: 10)
        XCTAssertEqual(totals.count, 3)
        XCTAssertEqual(totals[0].network, "Big")
        XCTAssertEqual(totals[0].rx, 5000)
        XCTAssertTrue(totals.contains { $0.network == nil && $0.rx == 300 })
    }

    func testCompactionPreservesTotalsAndNetworks() {
        let now = Date()
        let old = now.addingTimeInterval(-10 * 86_400)
        // 300 old rows across 3 days and 2 network labels.
        for i in 0..<300 {
            let ts = old.addingTimeInterval(Double((i % 3) * 86_400 + (i / 3) * 60))
            db.addUsage(ts: ts, rx: 1000, tx: 500, network: i % 2 == 0 ? "Net" : nil)
        }
        // Recent rows must survive untouched.
        db.addUsage(ts: now.addingTimeInterval(-100), rx: 42, tx: 24, network: "Now")

        let before = db.usageTotal(from: nil)
        db.compactUsage(olderThan: now.addingTimeInterval(-7 * 86_400))
        let after = db.usageTotal(from: nil)

        XCTAssertEqual(before.rx, after.rx, "compaction must not change totals")
        XCTAssertEqual(before.tx, after.tx)

        let oldRows = db.usageRows(from: nil).filter { $0.ts < now.addingTimeInterval(-7 * 86_400) }
        XCTAssertLessThanOrEqual(oldRows.count, 6, "3 days × 2 networks should collapse to ≤6 rows")

        // Network attribution survives the rewrite.
        let networks = db.networkTotals(from: nil, limit: 10)
        XCTAssertEqual(networks.first { $0.network == "Net" }?.rx, 150 * 1000)
        XCTAssertEqual(networks.first { $0.network == nil }?.rx, 150 * 1000)
        XCTAssertEqual(networks.first { $0.network == "Now" }?.rx, 42)

        // Running again on already-compact data is a no-op.
        db.compactUsage(olderThan: now.addingTimeInterval(-7 * 86_400))
        XCTAssertEqual(db.usageTotal(from: nil).rx, after.rx)
    }

    func testTopApps() {
        db.addAppUsage(day: "2026-07-20", app: "Chrome", rx: 100, tx: 10)
        db.addAppUsage(day: "2026-07-21", app: "Chrome", rx: 200, tx: 20)
        db.addAppUsage(day: "2026-07-21", app: "Slack", rx: 50, tx: 5)
        // Upsert accumulates within a day.
        db.addAppUsage(day: "2026-07-21", app: "Slack", rx: 25, tx: 5)

        let top = db.topApps(fromDay: "2026-07-20", limit: 10)
        XCTAssertEqual(top.first?.app, "Chrome")
        XCTAssertEqual(top.first?.rx, 300)
        XCTAssertEqual(top.last?.rx, 75)

        // Day filter.
        let recent = db.topApps(fromDay: "2026-07-21", limit: 10)
        XCTAssertEqual(recent.first { $0.app == "Chrome" }?.rx, 200)
    }

    func testSpeedTestsRoundTrip() {
        let now = Date()
        db.addSpeedTest(ts: now.addingTimeInterval(-60), down: 700, up: 650, latency: 7.5, dns: 2)
        db.addSpeedTest(ts: now, down: 800, up: 750, latency: nil, dns: nil)

        let all = db.speedTests(from: nil)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].down, 700)
        XCTAssertEqual(all[0].latency, 7.5)
        XCTAssertNil(all[1].latency)

        let recent = db.speedTests(from: now.addingTimeInterval(-30))
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent[0].down, 800)
    }

    func testTrendStriding() {
        let now = Date()
        // 2000 rows, 30 s apart.
        for i in 0..<2000 {
            db.addTrend(TrendRow(ts: now.addingTimeInterval(Double(-i * 30)), rssi: -50 - (i % 30),
                                 noise: -95, txRate: 500, latency: 10,
                                 rxBps: 1000, txBps: 500, channel: 100))
        }
        let rows = db.trendRows(from: now.addingTimeInterval(-2001 * 30), maxPoints: 700)
        XCTAssertLessThanOrEqual(rows.count, 701, "strided query must cap what leaves the DB")
        XCTAssertGreaterThan(rows.count, 500, "but should still return a dense series")
        // Ordered by time.
        XCTAssertTrue(zip(rows, rows.dropFirst()).allSatisfy { $0.ts <= $1.ts })
    }
}

// MARK: - Usage chart domain (day-rollover regression)

final class UsageDomainTests: XCTestCase {
    /// The newest bucket's full slot must fit inside the domain — otherwise
    /// the current day/hour/month bar clips past the plot edge (the
    /// after-midnight sliver bug).
    @MainActor
    func testDomainContainsCurrentBucketSlot() {
        let cal = Calendar.current
        // Just after midnight — the failure case.
        let now = cal.startOfDay(for: Date()).addingTimeInterval(40 * 60)

        for range in UsageRange.allCases {
            let domain = UsageView.xDomain(range: range, now: now, since: now.addingTimeInterval(-90 * 86_400))
            let unit: Calendar.Component
            switch range {
            case .day: unit = .hour
            case .week, .month: unit = .day
            case .year, .all: unit = .month
            }
            let slot = cal.dateInterval(of: unit, for: now)!
            XCTAssertGreaterThanOrEqual(domain.upperBound, slot.end,
                "\(range.rawValue): current bucket slot must end inside the domain")
            XCTAssertLessThanOrEqual(domain.lowerBound, slot.start)
        }
    }

    @MainActor
    func testWeekDomainSpansSevenDays() {
        let cal = Calendar.current
        let now = Date()
        let domain = UsageView.xDomain(range: .week, now: now, since: nil)
        let days = cal.dateComponents([.day], from: domain.lowerBound, to: domain.upperBound).day!
        XCTAssertEqual(days, 7)
    }
}
