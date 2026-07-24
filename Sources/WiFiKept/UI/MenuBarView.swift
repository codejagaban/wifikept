import SwiftUI

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case iconOnly = "Icon only"
    case quality = "Signal quality %"
    case rssi = "RSSI (dBm)"
    case linkRate = "Link rate"
    case latency = "Latency"
    case download = "Download B/s"
    case upload = "Upload B/s"
    case usageToday = "Data used today"
    var id: String { rawValue }

    /// Symbol shown in the menu bar (and the Settings picker) for this metric.
    var icon: String {
        switch self {
        case .iconOnly, .quality: return "wifi"
        case .rssi: return "antenna.radiowaves.left.and.right"
        case .linkRate: return "gauge.with.needle"
        case .latency: return "clock"
        case .download: return "arrow.down.circle"
        case .upload: return "arrow.up.circle"
        case .usageToday: return "chart.bar.fill"
        }
    }

    /// Fixed label width so the menu bar item doesn't resize as values tick.
    var labelWidth: CGFloat? {
        switch self {
        case .iconOnly: return nil
        case .quality: return 38      // "100%"
        case .rssi: return 34         // "-100"
        case .linkRate: return 38     // "1200"
        case .latency: return 48      // "999ms"
        case .download, .upload: return 66  // "999 KB/s"
        case .usageToday: return 60   // "99.9 GB"
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var app = AppState.shared
    @AppStorage("menubar.metric") private var metricRaw = MenuBarMetric.quality.rawValue

    var body: some View {
        let metric = MenuBarMetric(rawValue: metricRaw) ?? .quality
        HStack(spacing: 4) {
            Image(systemName: app.snap.connected ? metric.icon : "wifi.slash")
            if let text = labelText(metric) {
                Text(text)
                    .monospacedDigit()
                    .frame(width: app.snap.connected ? metric.labelWidth : nil,
                           alignment: .leading)
            }
        }
    }

    private func labelText(_ metric: MenuBarMetric) -> String? {
        guard app.snap.connected else { return nil }
        switch metric {
        case .iconOnly: return nil
        case .quality: return "\(app.snap.qualityPercent)%"
        case .rssi: return "\(app.snap.rssi)"
        case .linkRate: return "\(Int(app.snap.txRate))"
        case .latency: return app.latencyMs.map { "\(Int($0))ms" }
        case .download: return Fmt.bytesPerSec(app.rxBps)
        case .upload: return Fmt.bytesPerSec(app.txBps)
        case .usageToday:
            let t = app.usageTotals().today
            return Fmt.bytes(t.rx + t.tx)
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("appearance") private var appearanceRaw = AppearanceSetting.system.rawValue
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private var snap: WiFiSnapshot { app.snap }

    private var qualityColor: Color {
        switch snap.qualityRating {
        case "Excellent", "Good": return Theme.green
        case "Fair": return Theme.yellow
        default: return Theme.red
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            headerCard
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                cell(icon: "clock.fill", color: Theme.orange, title: "Latency",
                     value: app.latencyMs.map { Fmt.ms($0) } ?? "—")
                cell(icon: "wifi.router.fill", color: Theme.blue, title: "Standard",
                     value: snap.standard)
                cell(icon: "lock.shield.fill", color: Theme.green, title: "Security",
                     value: snap.security)
                cell(icon: "antenna.radiowaves.left.and.right", color: Theme.teal, title: "Band",
                     value: snap.bandLabel)
                cell(icon: "arrow.down", color: Theme.textSecondary, title: "Receiving",
                     value: Fmt.bytesPerSec(app.rxBps))
                cell(icon: "arrow.up", color: Theme.purple, title: "Sending",
                     value: Fmt.bytesPerSec(app.txBps))
                cell(icon: "chart.bar.fill", color: Theme.pink, title: "Today",
                     value: todayTotal)
                cell(icon: "calendar", color: Theme.indigo, title: "This Week",
                     value: weekTotal)
            }
            if let top = app.liveTalkers.first, top.rxBps + top.txBps >= 200 {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.orange)
                    Text(top.app)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("↓ \(Fmt.bytesPerSec(top.rxBps))  ↑ \(Fmt.bytesPerSec(top.txBps))")
                        .font(.mono(11, .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(glassShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
            }
            buttonsRow
        }
        .padding(12)
        .frame(width: 360)
        .background(VisualEffectBackground().ignoresSafeArea())
        .preferredColorScheme((AppearanceSetting(rawValue: appearanceRaw) ?? .system).scheme)
    }

    private var todayTotal: String {
        let t = app.usageTotals().today
        return Fmt.bytes(t.rx + t.tx)
    }

    private var weekTotal: String {
        let t = app.usageTotals().week
        return Fmt.bytes(t.rx + t.tx)
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(qualityColor.opacity(0.16)).frame(width: 46, height: 46)
                Image(systemName: snap.connected ? "wifi" : "wifi.slash")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(qualityColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(snap.ssid ?? (snap.connected ? "Wi-Fi" : "Not Connected"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(snap.qualityRating)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(qualityColor)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(snap.rssi) dBm")
                    .font(.mono(13, .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(snap.channel > 0 ? "Ch \(snap.channel) · \(snap.bandLabel)" : "—")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .background(glassShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
    }

    private func cell(icon: String, color: Color, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(value)
                .font(.display(15, .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(glassShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
    }

    private var buttonsRow: some View {
        HStack(spacing: 10) {
            barButton(icon: "macwindow", help: "Open WiFiKept") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            barButton(icon: "gearshape.fill", help: "Settings") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            barButton(icon: "power", help: "Quit") {
                AppState.shared.flushUsage()
                NSApp.terminate(nil)
            }
        }
    }

    private func barButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(glassShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}


/// Small frosted panel used by the popover cells and buttons.
@ViewBuilder
func glassShape(_ shape: some InsettableShape) -> some View {
    shape.fill(Theme.cardTranslucent)
        .overlay(shape.strokeBorder(Theme.stroke, lineWidth: 1))
}
