import Foundation
import SystemConfiguration
import Darwin

/// IP addresses, gateway and DNS servers — the slow-changing side of the
/// connection, read from getifaddrs and the SystemConfiguration dynamic store.
enum NetworkInfo {
    static func addresses(interface: String) -> (v4: String?, v6: String?) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return (nil, nil) }
        defer { freeifaddrs(ifaddr) }

        var v4: String?
        var v6: String?
        var p = ifaddr
        while let cur = p {
            let ifa = cur.pointee
            p = ifa.ifa_next
            guard let addr = ifa.ifa_addr, String(cString: ifa.ifa_name) == interface else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let family = addr.pointee.sa_family
            if family == UInt8(AF_INET), v4 == nil {
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    v4 = String(cString: host)
                }
            } else if family == UInt8(AF_INET6), v6 == nil {
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let s = String(cString: host).components(separatedBy: "%").first ?? ""
                    if !s.hasPrefix("fe80") && !s.isEmpty { v6 = s }
                }
            }
        }
        return (v4, v6)
    }

    static func gateway() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "WiFiKept" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString),
              let dict = value as? [String: Any] else { return nil }
        return dict["Router"] as? String
    }

    static func dnsServers() -> [String] {
        guard let store = SCDynamicStoreCreate(nil, "WiFiKept" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString),
              let dict = value as? [String: Any] else { return [] }
        return dict["ServerAddresses"] as? [String] ?? []
    }

    /// Wall time for one synchronous DNS resolution, in milliseconds.
    static func dnsLookupMs(host: String) -> Double? {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
                             ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil,
                             ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        let t0 = CFAbsoluteTimeGetCurrent()
        let rc = getaddrinfo(host, nil, &hints, &res)
        let elapsed = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        if let res { freeaddrinfo(res) }
        return rc == 0 ? elapsed : nil
    }
}
