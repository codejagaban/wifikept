import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject var app: AppState
    @State private var totals = UsageTotals()

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
            headerCard
            throughputCard
            quickGrid
            InsightBox(
                title: "Connection Insight",
                text: app.insights.insight(
                    for: "overview",
                    context: overviewContext,
                    fallback: FallbackInsight.signal(snap)),
                tint: Theme.blue)
        }
        .onAppear { totals = app.usageTotals() }
        .onChange(of: app.usageStamp) { totals = app.usageTotals() }
    }

    private var headerCard: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(qualityColor.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: snap.connected ? "wifi" : "wifi.slash")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(qualityColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(snap.ssid ?? (snap.connected ? "Wi-Fi Network" : "Not Connected"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(snap.qualityRating)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(qualityColor)
                if snap.ssid == nil && snap.connected {
                    Text("Grant Location access to see the network name")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(snap.rssi) dBm")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Text(snap.channel > 0 ? "Ch \(snap.channel) · \(snap.bandLabel)" : "—")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .card(padding: 22)
    }

    private var throughputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live throughput")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                HStack(spacing: 16) {
                    Label(Fmt.bytesPerSec(app.rxBps), systemImage: "arrow.down")
                        .foregroundStyle(Theme.blue)
                    Label(Fmt.bytesPerSec(app.txBps), systemImage: "arrow.up")
                        .foregroundStyle(Theme.seriesSecondary)
                }
                .font(.system(size: 13, weight: .semibold))
            }
            Chart {
                ForEach(Array(app.liveHistory.enumerated()), id: \.offset) { _, point in
                    AreaMark(x: .value("Time", point.date),
                             y: .value("B/s", point.rx),
                             series: .value("Series", "Down"))
                        .foregroundStyle(LinearGradient(colors: [Theme.blue.opacity(0.35), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", point.date),
                             y: .value("B/s", point.rx),
                             series: .value("Series", "Down"))
                        .foregroundStyle(Theme.blue)
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", point.date),
                             y: .value("B/s", point.tx),
                             series: .value("Series", "Up"))
                        .foregroundStyle(Theme.seriesSecondary)
                        .interpolationMethod(.monotone)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Theme.gridline)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(Fmt.bytesPerSec(v))
                        }
                    }
                    .foregroundStyle(Theme.textTertiary)
                }
            }
            .chartLegend(.hidden)
            .frame(height: 130)
        }
        .card(padding: 20)
    }

    private var quickGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            MetricCard(icon: "gauge.with.needle", iconColor: Theme.textSecondary,
                       title: "Link Rate", value: snap.txRate > 0 ? "\(Int(snap.txRate)) Mbps" : "—")
            MetricCard(icon: "clock.fill", iconColor: Theme.orange,
                       title: "Latency", value: app.latencyMs.map { Fmt.ms($0) } ?? "—")
            MetricCard(icon: "wifi", iconColor: Theme.teal,
                       title: "Standard", value: snap.standard)
            MetricCard(icon: "chart.bar.fill", iconColor: Theme.purple,
                       title: "Today", value: Fmt.bytes(totals.today.rx + totals.today.tx))
        }
    }

    private var overviewContext: String {
        "SSID \(snap.ssid ?? "unknown"), RSSI \(snap.rssi) dBm (\(snap.qualityRating)), SNR \(snap.snr) dB, link \(Int(snap.txRate)) Mbps, \(snap.standard) on \(snap.bandLabel), latency \(app.latencyMs.map { Fmt.ms($0) } ?? "n/a"), live throughput down \(Fmt.bytesPerSec(app.rxBps)) up \(Fmt.bytesPerSec(app.txBps)), data used today \(Fmt.bytes(totals.today.rx + totals.today.tx))."
    }
}
