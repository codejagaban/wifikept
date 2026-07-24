import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var tester = AppState.shared.speed
    @State private var totals = UsageTotals()
    @State private var netUsage: (network: String, rx: Int64, tx: Int64)?

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
            HStack(spacing: 14) {
                heroCard
                speedCard
            }
            .frame(height: 212)
            HStack(spacing: 14) {
                MetricCard(icon: "clock.fill", iconColor: Theme.orange,
                           title: "Latency",
                           value: app.latencyMs.map { Fmt.ms($0) } ?? "—",
                           detail: latencyRating)
                MetricCard(icon: "wifi.router.fill", iconColor: Theme.blue,
                           title: "Wi-Fi Standard", value: snap.standard,
                           detail: snap.bandLabel)
                MetricCard(icon: "lock.shield.fill", iconColor: Theme.green,
                           title: "Security", value: securityGrade,
                           detail: snap.security)
                MetricCard(icon: "chart.pie.fill", iconColor: Theme.teal,
                           title: "This Network",
                           value: netUsage.map { Fmt.bytes($0.rx + $0.tx) } ?? "—",
                           detail: "all-time here")
            }
            HStack(spacing: 14) {
                liveCard(icon: "arrow.down", chipColor: Theme.blue,
                         title: "Receiving", value: Fmt.bytesPerSec(app.rxBps))
                liveCard(icon: "arrow.up", chipColor: Theme.purple,
                         title: "Sending", value: Fmt.bytesPerSec(app.txBps))
            }
            connectionReport
        }
        .onAppear {
            totals = app.usageTotals()
            netUsage = app.currentNetworkAllTime()
        }
        .onChange(of: app.usageStamp) {
            totals = app.usageTotals()
            netUsage = app.currentNetworkAllTime()
        }
        .onChange(of: snap.ssid) {
            netUsage = app.currentNetworkAllTime()
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        HStack(spacing: 24) {
            ZStack {
                ArcGauge(progress: Double(snap.qualityPercent) / 100,
                         color: qualityColor, lineWidth: 11, size: 120)
                VStack(spacing: 0) {
                    Text("\(snap.qualityPercent)")
                        .font(.display(32, .bold))
                        .foregroundStyle(qualityColor)
                    Text("%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .offset(y: -3)
            }

            Rectangle().fill(Theme.stroke).frame(width: 1).padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(snap.connected ? Theme.green : Theme.red)
                        .frame(width: 9, height: 9)
                    Text(snap.ssid ?? (snap.connected ? "Wi-Fi Network" : "Not Connected"))
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(snap.qualityRating)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(qualityColor)
                metaLine
                    .padding(.top, 4)
                if snap.ssid == nil && snap.connected {
                    Text("Grant Location access to see the network name")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .card(padding: 22)
    }

    private var metaLine: some View {
        (Text("RSSI ").foregroundStyle(Theme.textTertiary)
            + Text("\(snap.rssi) dBm").foregroundStyle(Theme.textPrimary).fontWeight(.semibold)
            + Text("  ·  SNR ").foregroundStyle(Theme.textTertiary)
            + Text("\(snap.snr) dB").foregroundStyle(Theme.textPrimary).fontWeight(.semibold)
            + Text("  ·  Ch ").foregroundStyle(Theme.textTertiary)
            + Text("\(snap.channel)").foregroundStyle(Theme.textPrimary).fontWeight(.semibold))
            .font(.system(size: 14))
    }

    // MARK: - Speed summary

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.teal)
                Text("SPEED")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                speedRow(icon: "arrow.down", color: Theme.blue,
                         value: tester.result.map { String(format: "%.0f Mbps", $0.downloadMbps) } ?? "—")
                speedRow(icon: "arrow.up", color: Theme.green,
                         value: tester.result.map { String(format: "%.0f Mbps", $0.uploadMbps) } ?? "—")
            }
            Spacer()
            HStack {
                Spacer()
                Text(speedFootnote)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .card(padding: 20)
        .frame(width: 320)
    }

    private func speedRow(icon: String, color: Color, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 21, height: 21)
                .background(Circle().fill(color))
            Text(value)
                .font(.display(21, .bold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var speedFootnote: String {
        if tester.isRunning { return "Testing…" }
        if tester.cooldownRemaining > 0 { return "Wait \(tester.cooldownRemaining)s" }
        if let r = tester.result { return "Tested \(Fmt.ago(r.date))" }
        return "Run a test in Speed"
    }

    // MARK: - Live activity

    private func liveCard(icon: String, chipColor: Color, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 21, height: 21)
                    .background(Circle().fill(chipColor))
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(chipColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(chipColor.opacity(0.15)))
            }
            HStack(alignment: .lastTextBaseline) {
                Text(value)
                    .font(.display(23, .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.default, value: value)
                Spacer()
                Text("Wi-Fi Activity")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Security grade

    private var securityGrade: String {
        switch snap.security {
        case let s where s.hasPrefix("WPA3"): return "A+"
        case "OWE": return "A"
        case "WPA2 Enterprise": return "A-"
        case "WPA2 Personal": return "B+"
        case let s where s.hasPrefix("WPA"): return "C"
        case "WEP": return "D"
        case "Open": return "F"
        default: return "—"
        }
    }

    private var latencyRating: String {
        guard let l = app.latencyMs else { return "" }
        switch l {
        case ..<20: return "Excellent"
        case ..<50: return "Good"
        case ..<100: return "Fair"
        default: return "High"
        }
    }

    // MARK: - Connection report

    private var connectionReport: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.aiGradient)
                Text("CONNECTION REPORT")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(reportLead)
                .font(.system(size: 13.5))
                .lineSpacing(4)
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Theme.stroke).frame(height: 1)
            VStack(alignment: .leading, spacing: 11) {
                reportRow(icon: signalBullet.0, color: signalBullet.1, text: signalBullet.2)
                reportRow(icon: "bolt.fill", color: Theme.yellow, text: speedBullet)
                reportRow(icon: "chart.bar.fill", color: Theme.teal, text: usageBullet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func reportRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reportLead: String {
        let fallback: String
        if !snap.connected {
            fallback = "Not connected to Wi-Fi right now."
        } else if let r = tester.result {
            fallback = String(format: "Your connection is in %@ shape with %.0f Mbps download.",
                              snap.qualityRating.lowercased(), r.downloadMbps)
        } else {
            fallback = "Your connection looks \(snap.qualityRating.lowercased()) — run a speed test for the full picture."
        }
        return app.insights.insight(for: "overview", context: reportContext, fallback: fallback)
    }

    private var signalBullet: (String, Color, String) {
        if !snap.connected {
            return ("xmark.circle.fill", Theme.red, "No active Wi-Fi connection.")
        }
        let icon = snap.rssi >= -70 ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        let color = snap.rssi >= -70 ? Theme.green : Theme.yellow
        let strength = snap.rssi >= -60 ? "Strong" : snap.rssi >= -70 ? "Good" : "Weak"
        return (icon, color, "\(strength) signal at \(snap.rssi) dBm (\(snap.qualityPercent)%).")
    }

    private var speedBullet: String {
        guard let r = tester.result else {
            return "Run a speed test to grade this link."
        }
        let verdict = r.downloadMbps >= 100 ? "great for streaming and large downloads"
            : r.downloadMbps >= 25 ? "fine for everyday use" : "on the slow side"
        return String(format: "%.0f Mbps down, %.0f Mbps up — %@.", r.downloadMbps, r.uploadMbps, verdict)
    }

    private var usageBullet: String {
        "\(Fmt.bytes(totals.today.rx + totals.today.tx)) used today · \(Fmt.bytes(totals.week.rx + totals.week.tx)) this week."
    }

    private var reportContext: String {
        "SSID \(snap.ssid ?? "unknown"), RSSI \(snap.rssi) dBm (\(snap.qualityRating)), SNR \(snap.snr) dB, link \(Int(snap.txRate)) Mbps, \(snap.standard) on \(snap.bandLabel), security \(snap.security), latency \(app.latencyMs.map { Fmt.ms($0) } ?? "n/a"), last speed test \(tester.result.map { String(format: "%.0f down / %.0f up Mbps", $0.downloadMbps, $0.uploadMbps) } ?? "none"), usage today \(Fmt.bytes(totals.today.rx + totals.today.tx))."
    }
}
