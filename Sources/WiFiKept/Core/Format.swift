import Foundation

enum Fmt {
    /// "4.2 GB", "312 MB" — decimal units (1 GB = 10⁹), matching how macOS,
    /// routers and ISPs count.
    static func bytes(_ v: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: v)
    }

    /// "153 Mbps", "1.2 Gbps"
    static func bitsPerSec(_ bps: Double) -> String {
        switch bps {
        case ..<1_000: return String(format: "%.0f bps", bps)
        case ..<1_000_000: return String(format: "%.0f Kbps", bps / 1_000)
        case ..<1_000_000_000:
            let v = bps / 1_000_000
            return v >= 100 ? String(format: "%.0f Mbps", v) : String(format: "%.1f Mbps", v)
        default: return String(format: "%.2f Gbps", bps / 1_000_000_000)
        }
    }

    /// "487 B/s", "1.2 MB/s"
    static func bytesPerSec(_ v: Double) -> String {
        switch v {
        case ..<1024: return String(format: "%.0f B/s", v)
        case ..<1_048_576: return String(format: "%.0f KB/s", v / 1024)
        case ..<1_073_741_824:
            let m = v / 1_048_576
            return m >= 100 ? String(format: "%.0f MB/s", m) : String(format: "%.1f MB/s", m)
        default: return String(format: "%.2f GB/s", v / 1_073_741_824)
        }
    }

    /// "20 seconds ago", "3 min ago"
    static func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        switch s {
        case ..<5: return "just now"
        case ..<60: return "\(s) seconds ago"
        case ..<3600: return "\(s / 60) min ago"
        case ..<86_400: return "\(s / 3600) h ago"
        default: return "\(s / 86_400) d ago"
        }
    }

    static func ms(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f ms", v) : String(format: "%.0f ms", v)
    }
}

/// Signal quality mapping shared by every surface.
enum SignalQuality {
    /// Piecewise-linear percent from RSSI: −50 → 100 … −95 → 0.
    static func percent(rssi: Int) -> Int {
        let anchors: [(Double, Double)] = [(-50, 100), (-60, 85), (-70, 65), (-80, 40), (-95, 0)]
        let r = Double(rssi)
        if r >= anchors[0].0 { return 100 }
        for i in 0..<(anchors.count - 1) {
            let (x0, y0) = anchors[i], (x1, y1) = anchors[i + 1]
            if r >= x1 {
                return Int((y1 + (r - x1) / (x0 - x1) * (y0 - y1)).rounded())
            }
        }
        return 0
    }

    static func rating(rssi: Int) -> String {
        switch rssi {
        case (-60)...: return "Excellent"
        case (-70)...: return "Good"
        case (-80)...: return "Fair"
        default: return "Poor"
        }
    }
}
