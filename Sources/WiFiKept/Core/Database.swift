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
