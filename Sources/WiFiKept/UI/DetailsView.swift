import SwiftUI

struct DetailsView: View {
    @EnvironmentObject var app: AppState

    private var snap: WiFiSnapshot { app.snap }
    private var cols: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 14), count: 3) }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                SectionLabel(text: "Addresses")
                LazyVGrid(columns: cols, spacing: 14) {
                    CopyCard(icon: "4.circle.fill", iconColor: Theme.blue,
                             title: "IPv4 Address", value: snap.ipv4)
                    CopyCard(icon: "6.circle.fill", iconColor: Theme.teal,
                             title: "IPv6 Address", value: snap.ipv6)
                    CopyCard(icon: "antenna.radiowaves.left.and.right.circle.fill", iconColor: Theme.green,
                             title: "BSSID", value: snap.bssid,
                             trailing: snap.bssid == nil ? "needs Location" : "")
                }
            }

            VStack(spacing: 12) {
                SectionLabel(text: "Network")
                LazyVGrid(columns: cols, spacing: 14) {
                    CopyCard(icon: "arrow.triangle.branch", iconColor: Theme.orange,
                             title: "Gateway", value: snap.gateway)
                    CopyCard(icon: "memorychip", iconColor: Theme.pink,
                             title: "MAC Address", value: snap.macAddress)
                    CopyCard(icon: "cable.connector", iconColor: Theme.textSecondary,
                             title: "Interface", value: snap.interfaceName,
                             trailing: snap.interfaceMode)
                }
            }

            VStack(spacing: 12) {
                SectionLabel(text: "Radio")
                LazyVGrid(columns: cols, spacing: 14) {
                    CopyCard(icon: "lock.shield.fill", iconColor: Theme.green,
                             title: "Security", value: snap.security)
                    CopyCard(icon: "antenna.radiowaves.left.and.right", iconColor: Theme.teal,
                             title: "Band", value: snap.bandLabel)
                    CopyCard(icon: "globe", iconColor: Theme.blue,
                             title: "Country Code", value: snap.countryCode)
                }
            }

            InsightBox(
                title: "Network Insight",
                text: app.insights.insight(
                    for: "details",
                    context: "Network \(snap.ssid ?? "unknown"): \(snap.security) security, \(snap.standard) (\(snap.standardDetail)), \(snap.bandLabel) band, channel \(snap.channel), gateway \(snap.gateway ?? "n/a").",
                    fallback: FallbackInsight.details(snap)),
                tint: Theme.indigo)
        }
    }
}
