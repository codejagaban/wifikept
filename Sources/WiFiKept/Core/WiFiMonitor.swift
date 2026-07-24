import Foundation
import CoreWLAN
import CoreLocation

/// One reading of everything CoreWLAN knows about the current connection.
struct WiFiSnapshot: Equatable {
    var connected = false
    var ssid: String?
    var bssid: String?
    var rssi = 0            // dBm
    var noise = 0           // dBm
    var txRate: Double = 0  // Mbps
    var txPower = 0         // mW
    var channel = 0
    var bandLabel = "—"     // "5 GHz"
    var widthMHz = 0
    var standard = "—"      // "Wi-Fi 6"
    var standardDetail = "" // "802.11ax · 9.6 Gbps max"
    var security = "—"
    var countryCode: String?
    var interfaceName = "en0"
    var interfaceMode = "—"
    var macAddress: String?
    var ipv4: String?
    var ipv6: String?
    var gateway: String?

    var snr: Int { rssi - noise }
    var qualityPercent: Int { connected ? SignalQuality.percent(rssi: rssi) : 0 }
    var qualityRating: String { connected ? SignalQuality.rating(rssi: rssi) : "Offline" }

    static let empty = WiFiSnapshot()
}

/// Polls CoreWLAN and owns the Location permission dance that macOS
/// requires before it will reveal SSID/BSSID to a third-party app.
final class WiFiMonitor: NSObject, CLLocationManagerDelegate {
    private let client = CWWiFiClient.shared()
    private let location = CLLocationManager()
    private(set) var locationAuthorized = false

    override init() {
        super.init()
        location.delegate = self
        let status = location.authorizationStatus
        locationAuthorized = (status == .authorizedAlways)
        if status == .notDetermined {
            location.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAuthorized = (manager.authorizationStatus == .authorizedAlways)
    }

    var interfaceName: String {
        client.interface()?.interfaceName ?? "en0"
    }

    func snapshot() -> WiFiSnapshot {
        var s = WiFiSnapshot()
        guard let iface = client.interface() else { return s }
        s.interfaceName = iface.interfaceName ?? "en0"
        s.ssid = iface.ssid()
        s.bssid = iface.bssid()
        s.rssi = iface.rssiValue()
        s.noise = iface.noiseMeasurement()
        s.txRate = iface.transmitRate()
        s.txPower = iface.transmitPower()
        s.macAddress = iface.hardwareAddress()
        s.countryCode = iface.countryCode()
        s.connected = iface.serviceActive() && s.rssi != 0

        if let ch = iface.wlanChannel() {
            s.channel = ch.channelNumber
            switch ch.channelBand {
            case .band2GHz: s.bandLabel = "2.4 GHz"
            case .band5GHz: s.bandLabel = "5 GHz"
            case .band6GHz: s.bandLabel = "6 GHz"
            default: s.bandLabel = "—"
            }
            switch ch.channelWidth {
            case .width20MHz: s.widthMHz = 20
            case .width40MHz: s.widthMHz = 40
            case .width80MHz: s.widthMHz = 80
            case .width160MHz: s.widthMHz = 160
            default: s.widthMHz = 0
            }
        }

        let phy = iface.activePHYMode()
        (s.standard, s.standardDetail) = Self.standardLabel(phy: phy, band: s.bandLabel)

        s.security = Self.securityLabel(iface.security())

        switch iface.interfaceMode() {
        case .station: s.interfaceMode = "Station"
        case .hostAP: s.interfaceMode = "Access Point"
        case .IBSS: s.interfaceMode = "Ad-hoc"
        default: s.interfaceMode = "—"
        }

        let addrs = NetworkInfo.addresses(interface: s.interfaceName)
        s.ipv4 = addrs.v4
        s.ipv6 = addrs.v6
        s.gateway = NetworkInfo.gateway()
        return s
    }

    private static func standardLabel(phy: CWPHYMode, band: String) -> (String, String) {
        switch phy.rawValue {
        case 1: return ("Wi-Fi 2", "802.11a · 54 Mbps max")
        case 2: return ("Wi-Fi 1", "802.11b · 11 Mbps max")
        case 3: return ("Wi-Fi 3", "802.11g · 54 Mbps max")
        case 4: return ("Wi-Fi 4", "802.11n · 600 Mbps max")
        case 5: return ("Wi-Fi 5", "802.11ac · 6.9 Gbps max")
        case 6:
            let name = band == "6 GHz" ? "Wi-Fi 6E" : "Wi-Fi 6"
            return (name, "802.11ax · 9.6 Gbps max")
        case 7...: return ("Wi-Fi 7", "802.11be · 46 Gbps max")
        default: return ("—", "")
        }
    }

    private static func securityLabel(_ sec: CWSecurity) -> String {
        switch sec {
        case .none: return "Open"
        case .WEP, .dynamicWEP: return "WEP"
        case .wpaPersonal, .wpaPersonalMixed: return "WPA Personal"
        case .wpa2Personal, .personal: return "WPA2 Personal"
        case .wpaEnterprise, .wpaEnterpriseMixed: return "WPA Enterprise"
        case .wpa2Enterprise, .enterprise: return "WPA2 Enterprise"
        case .wpa3Personal, .wpa3Transition: return "WPA3 Personal"
        case .wpa3Enterprise: return "WPA3 Enterprise"
        case .OWE, .oweTransition: return "OWE"
        default: return "Unknown"
        }
    }
}
