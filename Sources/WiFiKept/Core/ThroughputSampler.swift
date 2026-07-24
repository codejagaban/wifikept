import Foundation
import Darwin

/// Reads 64-bit rx/tx byte counters for a network interface via
/// sysctl(NET_RT_IFLIST2). No privileges required.
struct InterfaceCounters {
    var rx: UInt64
    var tx: UInt64

    static func read(interface: String) -> InterfaceCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: size_t = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, u_int(mib.count), &buf, &len, nil, 0) == 0 else { return nil }

        var result: InterfaceCounters?
        buf.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let ifm = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard ifm.ifm_msglen > 0 else { break }
                if Int32(ifm.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= len {
                    let ifm2 = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    if if_indextoname(UInt32(ifm2.ifm_index), &name) != nil,
                       String(cString: name) == interface {
                        result = InterfaceCounters(rx: ifm2.ifm_data.ifi_ibytes,
                                                   tx: ifm2.ifm_data.ifi_obytes)
                    }
                }
                offset += Int(ifm.ifm_msglen)
            }
        }
        return result
    }
}

/// Tracks deltas between successive counter reads, tolerating counter
/// resets (reboot / interface bounce) by clamping to zero.
final class ThroughputSampler {
    private var last: InterfaceCounters?
    private var lastTime: Date?

    struct Sample {
        var rxDelta: UInt64
        var txDelta: UInt64
        var interval: TimeInterval
        var rxPerSec: Double { interval > 0 ? Double(rxDelta) / interval : 0 }
        var txPerSec: Double { interval > 0 ? Double(txDelta) / interval : 0 }
    }

    func sample(interface: String) -> Sample? {
        guard let now = InterfaceCounters.read(interface: interface) else {
            last = nil
            lastTime = nil
            return nil
        }
        let t = Date()
        defer { last = now; lastTime = t }
        guard let prev = last, let prevT = lastTime else { return nil }
        let dt = t.timeIntervalSince(prevT)
        guard dt > 0 else { return nil }
        let rx = now.rx >= prev.rx ? now.rx - prev.rx : 0
        let tx = now.tx >= prev.tx ? now.tx - prev.tx : 0
        return Sample(rxDelta: rx, txDelta: tx, interval: dt)
    }
}
