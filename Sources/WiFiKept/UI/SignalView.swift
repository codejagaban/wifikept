import SwiftUI

struct SignalView: View {
    @EnvironmentObject var app: AppState

    private var snap: WiFiSnapshot { app.snap }

    private var qualityColor: Color {
        switch snap.qualityRating {
        case "Excellent", "Good": return Theme.green
        case "Fair": return Theme.yellow
        default: return Theme.red
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            heroCard
            grid
            InsightBox(
                title: "Signal Insight",
                text: app.insights.insight(
                    for: "signal",
                    context: "RSSI \(snap.rssi) dBm, noise \(snap.noise) dBm, SNR \(snap.snr) dB, link rate \(Int(snap.txRate)) Mbps, channel \(snap.channel) (\(snap.bandLabel), \(snap.widthMHz) MHz wide), \(snap.standard).",
                    fallback: FallbackInsight.signal(snap)),
                tint: Theme.blue)
        }
    }

    private var heroCard: some View {
        HStack(spacing: 24) {
            VStack(spacing: 10) {
                ZStack {
                    ArcGauge(progress: Double(snap.qualityPercent) / 100,
                             color: qualityColor, lineWidth: 13, size: 150)
                    VStack(spacing: 0) {
                        Text("\(snap.qualityPercent)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("%")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .offset(y: -4)
                }
                Text(snap.qualityRating)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(qualityColor)
            }
            .frame(width: 190)

            Rectangle().fill(Theme.stroke).frame(width: 1).padding(.vertical, 4)

            VStack(spacing: 18) {
                MeterRow(
                    title: "Signal Strength",
                    valueText: "\(snap.rssi) dBm",
                    progress: Double(snap.qualityPercent) / 100,
                    color: qualityColor,
                    caption: "\(snap.qualityPercent)% — \(snap.qualityRating)")
                MeterRow(
                    title: "Noise Floor",
                    valueText: "\(snap.noise) dBm",
                    progress: noiseProgress,
                    color: Theme.textTertiary,
                    caption: noiseCaption)
                MeterRow(
                    title: "SNR",
                    valueText: "\(snap.snr) dB",
                    progress: min(1, Double(snap.snr) / 40),
                    color: snap.snr >= 20 ? Theme.green : snap.snr >= 12 ? Theme.yellow : Theme.red,
                    caption: snap.snr >= 25 ? "Clean channel" : snap.snr >= 15 ? "Usable channel" : "Noisy channel")
            }
        }
        .card(padding: 24)
    }

    /// A *quieter* (more negative) noise floor fills less of the bar.
    private var noiseProgress: Double {
        min(1, max(0.02, (Double(snap.noise) + 100) / 40))
    }

    private var noiseCaption: String {
        switch snap.noise {
        case ..<(-92): return "Very quiet — excellent"
        case ..<(-85): return "Quiet"
        case ..<(-78): return "Moderate noise"
        default: return "Loud noise floor"
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
            MetricCard(icon: "antenna.radiowaves.left.and.right", iconColor: Theme.blue,
                       title: "Channel", value: snap.channel > 0 ? "Ch \(snap.channel)" : "—",
                       detail: snap.bandLabel)
            MetricCard(icon: "square.3.layers.3d", iconColor: Theme.purple,
                       title: "Width", value: snap.widthMHz > 0 ? "\(snap.widthMHz) MHz" : "—",
                       detail: "channel bandwidth")
            MetricCard(icon: "wifi", iconColor: Theme.teal,
                       title: "Standard", value: snap.standard,
                       detail: snap.standardDetail)
            MetricCard(icon: "gauge.with.needle", iconColor: Theme.green,
                       title: "Link Rate", value: snap.txRate > 0 ? "\(Int(snap.txRate)) Mbps" : "—",
                       detail: "negotiated PHY rate")
            MetricCard(icon: "bolt.fill", iconColor: Theme.orange,
                       title: "TX Power", value: snap.txPower > 0 ? "\(snap.txPower) mW" : "—",
                       detail: snap.txPower >= 1000 ? "high power" : "normal power")
            MetricCard(icon: "globe", iconColor: Theme.indigo,
                       title: "BSSID", value: snap.bssid ?? "—",
                       detail: snap.bssid == nil ? "needs Location access" : "access point address",
                       monospacedValue: true)
        }
    }
}
