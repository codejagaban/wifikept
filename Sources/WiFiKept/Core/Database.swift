import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct TrendRow {
    var ts: Date
    var rssi: Int
    var noise: Int
    var txRate: Double
    var latency: Double?
    var rxBps: Double
    var txBps: Double
    var channel: Int
}

struct UsageRow {
    var ts: Date
    var rx: Int64
    var tx: Int64
}

struct SpeedRow {
    var ts: Date
    var down: Double
    var up: Double
    var latency: Double?
}

/// Tiny serial-queue SQLite wrapper. Two tables:
///   usage(ts, rx, tx)  — one row per flush (~1/min), kept forever
///   trend(ts, rssi, noise, txrate, latency, rxbps, txbps, channel) — 90-day window
final class Database {
    private var db: OpaquePointer?
    private let q = DispatchQueue(label: "wifikept.db")

    init(path: String) {
        q.sync {
            sqlite3_open(path, &db)
            exec("PRAGMA journal_mode=WAL")
            exec("""
                CREATE TABLE IF NOT EXISTS usage(
                    ts INTEGER PRIMARY KEY, rx INTEGER NOT NULL, tx INTEGER NOT NULL)
                """)
            exec("""
                CREATE TABLE IF NOT EXISTS trend(
                    ts INTEGER PRIMARY KEY, rssi INTEGER, noise INTEGER, txrate REAL,
                    latency REAL, rxbps REAL, txbps REAL, channel INTEGER)
                """)
            exec("""
                CREATE TABLE IF NOT EXISTS counter_state(
                    iface TEXT PRIMARY KEY, boot INTEGER, rx INTEGER, tx INTEGER, seen INTEGER)
                """)
            exec("""
                CREATE TABLE IF NOT EXISTS speedtest(
                    ts INTEGER PRIMARY KEY, down REAL, up REAL, latency REAL, dns REAL)
                """)
            exec("""
                CREATE TABLE IF NOT EXISTS app_usage(
                    day TEXT, app TEXT, rx INTEGER NOT NULL, tx INTEGER NOT NULL,
                    PRIMARY KEY(day, app))
                """)
        }
    }

    deinit { sqlite3_close(db) }

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Usage

    func addUsage(ts: Date, rx: Int64, tx: Int64) {
        guard rx > 0 || tx > 0 else { return }
        q.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, """
                INSERT INTO usage(ts, rx, tx) VALUES(?,?,?)
                ON CONFLICT(ts) DO UPDATE SET rx = rx + excluded.rx, tx = tx + excluded.tx
                """, -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, Int64(ts.timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 2, rx)
            sqlite3_bind_int64(stmt, 3, tx)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func usageTotal(from: Date?, to: Date? = nil) -> (rx: Int64, tx: Int64) {
        q.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT COALESCE(SUM(rx),0), COALESCE(SUM(tx),0) FROM usage WHERE ts >= ? AND ts < ?", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, Int64(from?.timeIntervalSince1970 ?? 0))
            sqlite3_bind_int64(stmt, 2, Int64(to?.timeIntervalSince1970 ?? Date.distantFuture.timeIntervalSince1970))
            var result: (Int64, Int64) = (0, 0)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = (sqlite3_column_int64(stmt, 0), sqlite3_column_int64(stmt, 1))
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    func usageRows(from: Date?) -> [UsageRow] {
        q.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT ts, rx, tx FROM usage WHERE ts >= ? ORDER BY ts", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, Int64(from?.timeIntervalSince1970 ?? 0))
            var rows: [UsageRow] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(UsageRow(
                    ts: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 0))),
                    rx: sqlite3_column_int64(stmt, 1),
                    tx: sqlite3_column_int64(stmt, 2)))
            }
            sqlite3_finalize(stmt)
            return rows
        }
    }

    func firstUsageDate() -> Date? {
        q.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT MIN(ts) FROM usage", -1, &stmt, nil)
            var result: Date?
            if sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                result = Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 0)))
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    // MARK: - Per-app usage

    func addAppUsage(day: String, app: String, rx: Int64, tx: Int64) {
        guard rx > 0 || tx > 0 else { return }
        q.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, """
                INSERT INTO app_usage(day, app, rx, tx) VALUES(?,?,?,?)
                ON CONFLICT(day, app) DO UPDATE SET rx = rx + excluded.rx, tx = tx + excluded.tx
                """, -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, app, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 3, rx)
            sqlite3_bind_int64(stmt, 4, tx)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func topApps(fromDay: String, limit: Int) -> [(app: String, rx: Int64, tx: Int64)] {
        q.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, """
                SELECT app, SUM(rx), SUM(tx) FROM app_usage WHERE day >= ?
                GROUP BY app ORDER BY SUM(rx) + SUM(tx) DESC LIMIT ?
                """, -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, fromDay, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            var rows: [(String, Int64, Int64)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append((String(cString: sqlite3_column_text(stmt, 0)),
                             sqlite3_column_int64(stmt, 1),
                             sqlite3_column_int64(stmt, 2)))
            }
            sqlite3_finalize(stmt)
            return rows
        }
    }

    // MARK: - Speed tests

    func addSpeedTest(ts: Date, down: Double, up: Double, latency: Double?, dns: Double?) {
        q.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO speedtest(ts, down, up, latency, dns) VALUES(?,?,?,?,?)", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, Int64(ts.timeIntervalSince1970))
            sqlite3_bind_double(stmt, 2, down)
            sqlite3_bind_double(stmt, 3, up)
            if let latency { sqlite3_bind_double(stmt, 4, latency) } else { sqlite3_bind_null(stmt, 4) }
            if let dns { sqlite3_bind_double(stmt, 5, dns) } else { sqlite3_bind_null(stmt, 5) }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func speedTests(from: Date?) -> [SpeedRow] {
        q.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT ts, down, up, latency FROM speedtest WHERE ts >= ? ORDER BY ts", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, Int64(from?.timeIntervalSince1970 ?? 0))
            var rows: [SpeedRow] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(SpeedRow(
                    ts: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 0))),
                    down: sqlite3_column_double(stmt, 1),
                    up: sqlite3_column_double(stmt, 2),
                    latency: sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 3)))
            }
            sqlite3_finalize(stmt)
            return rows
        }
    }

    // MARK: - Counter state (for crediting usage while the app was closed)

    struct CounterState {
        var boot: Int64
        var rx: Int64
        var tx: Int64
        var seen: Int64
    }

    func loadCounterStates() -> [String: CounterState] {
        q.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT iface, boot, rx, tx, seen FROM counter_state", -1, &stmt, nil)
            var result: [String: CounterState] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let iface = String(cString: sqlite3_column_text(stmt, 0))
                result[iface] = CounterState(boot: sqlite3_column_int64(stmt, 1),
                                             rx: sqlite3_column_int64(stmt, 2),
                                             tx: sqlite3_column_int64(stmt, 3),
                                             seen: sqlite3_column_int64(stmt, 4))
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    func saveCounterState(iface: String, boot: Int64, rx: Int64, tx: Int64, seen: Int64) {
        q.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, """
                INSERT OR REPLACE INTO counter_state(iface, boot, rx, tx, seen) VALUES(?,?,?,?,?)
                """, -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, iface, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, boot)
            sqlite3_bind_int64(stmt, 3, rx)
            sqlite3_bind_int64(stmt, 4, tx)
            sqlite3_bind_int64(stmt, 5, seen)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Trend

    func addTrend(_ r: TrendRow) {
        q.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, """
                INSERT OR REPLACE INTO trend(ts, rssi, noise, txrate, latency, rxbps, txbps, channel)
                VALUES(?,?,?,?,?,?,?,?)
                """, -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, Int64(r.ts.timeIntervalSince1970))
            sqlite3_bind_int(stmt, 2, Int32(r.rssi))
            sqlite3_bind_int(stmt, 3, Int32(r.noise))
            sqlite3_bind_double(stmt, 4, r.txRate)
            if let l = r.latency { sqlite3_bind_double(stmt, 5, l) } else { sqlite3_bind_null(stmt, 5) }
            sqlite3_bind_double(stmt, 6, r.rxBps)
            sqlite3_bind_double(stmt, 7, r.txBps)
            sqlite3_bind_int(stmt, 8, Int32(r.channel))
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func trendRows(from: Date) -> [TrendRow] {
        q.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, """
                SELECT ts, rssi, noise, txrate, latency, rxbps, txbps, channel
                FROM trend WHERE ts >= ? ORDER BY ts
                """, -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, Int64(from.timeIntervalSince1970))
            var rows: [TrendRow] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(TrendRow(
                    ts: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 0))),
                    rssi: Int(sqlite3_column_int(stmt, 1)),
                    noise: Int(sqlite3_column_int(stmt, 2)),
                    txRate: sqlite3_column_double(stmt, 3),
                    latency: sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 4),
                    rxBps: sqlite3_column_double(stmt, 5),
                    txBps: sqlite3_column_double(stmt, 6),
                    channel: Int(sqlite3_column_int(stmt, 7))))
            }
            sqlite3_finalize(stmt)
            return rows
        }
    }

    func firstTrendDate() -> Date? {
        q.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT MIN(ts) FROM trend", -1, &stmt, nil)
            var result: Date?
            if sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                result = Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 0)))
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    func pruneTrend(before: Date) {
        q.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM trend WHERE ts < ?", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, Int64(before.timeIntervalSince1970))
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }
}
