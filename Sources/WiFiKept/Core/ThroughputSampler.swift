import Foundation
import Darwin

struct InterfaceCounters {
    var rx: UInt64
    var tx: UInt64
}

/// Reads 64-bit rx/tx byte counters via sysctl(NET_RT_IFLIST2).
/// No privileges required. Counters are cumulative since boot.
enum InterfaceStats {
    /// Counters for every physical "en*" interface — Wi-Fi, Ethernet,
    /// Thunderbolt/USB adapters, iPhone tethering. Virtual interfaces
    /// (lo0, utun*, awdl0, llw0, bridge*) are deliberately excluded so VPN
    /// traffic isn't double-counted and local AirDrop chatter doesn't show up.
    static func readAll() -> [String: InterfaceCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: size_t = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return [:] }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, u_int(mib.count), &buf, &len, nil, 0) == 0 else { return [:] }

        var result: [String: InterfaceCounters] = [:]
        buf.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let ifm = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard ifm.ifm_msglen > 0 else { break }
                if Int32(ifm.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= len {
                    let ifm2 = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    if if_indextoname(UInt32(ifm2.ifm_index), &name) != nil {
                        let ifname = String(cString: name)
                        if ifname.hasPrefix("en") {
                            result[ifname] = InterfaceCounters(rx: ifm2.ifm_data.ifi_ibytes,
                                                               tx: ifm2.ifm_data.ifi_obytes)
                        }
                    }
                }
                offset += Int(ifm.ifm_msglen)
            }
        }
        return result
    }

    /// Unix timestamp of the last boot — counter epochs are per-boot.
    static func bootTime() -> Int64 {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0 else { return 0 }
        return Int64(tv.tv_sec)
    }
}

/// Tracks deltas between successive counter reads across all physical
/// interfaces, tolerating interfaces appearing/disappearing and counter
/// resets by clamping to zero per interface.
final class ThroughputSampler {
    private(set) var lastCounters: [String: InterfaceCounters] = [:]
    private var lastTime: Date?

    struct Sample {
        var rxDelta: UInt64
        var txDelta: UInt64
        var interval: TimeInterval
        var counters: [String: InterfaceCounters]
        var rxPerSec: Double { interval > 0 ? Double(rxDelta) / interval : 0 }
        var txPerSec: Double { interval > 0 ? Double(txDelta) / interval : 0 }
    }

    func sample() -> Sample? {
        let now = InterfaceStats.readAll()
        guard !now.isEmpty else { return nil }
        let t = Date()
        let prev = lastCounters
        let prevT = lastTime
        lastCounters = now
        lastTime = t
        guard let prevT, !prev.isEmpty else { return nil }
        let dt = t.timeIntervalSince(prevT)
        guard dt > 0 else { return nil }
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        for (name, cur) in now {
            guard let p = prev[name] else { continue }
            if cur.rx >= p.rx { rx += cur.rx - p.rx }
            if cur.tx >= p.tx { tx += cur.tx - p.tx }
        }
        return Sample(rxDelta: rx, txDelta: tx, interval: dt, counters: now)
    }
}
