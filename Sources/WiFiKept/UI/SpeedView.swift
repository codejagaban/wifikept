import SwiftUI

struct SpeedView: View {
    @EnvironmentObject var app: AppState
    @State private var now = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var tester: SpeedTester { app.speed }

    var body: some View {
        VStack(spacing: 16) {
            gaugesCard
            statusRow
            HStack(spacing: 14) {
                MetricCard(icon: "clock.fill", iconColor: Theme.orange,
                           title: "Latency",
                           value: tester.result?.latencyMs.map { Fmt.ms($0) } ?? app.latencyMs.map { Fmt.ms($0) } ?? "—",
                           detail: latencyRating)
                MetricCard(icon: "globe", iconColor: Theme.purple,
                           title: "DNS",
                           value: tester.result?.dnsMs.map { Fmt.ms($0) } ?? "—",
                           detail: dnsRating)
                MetricCard(icon: "checkmark.seal.fill", iconColor: Theme.green,
                           title: "Connection", value: connectionRating.0,
                           detail: connectionRating.1)
            }
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.textTertiary)
                Text("Speed test runs 4 parallel Cloudflare streams for ~6 seconds each way, like fast.com. Data used scales with your speed (typically 100–300 MB per run). Results reflect your internet connection, not Wi-Fi signal strength.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .card(padding: 14)
            InsightBox(
                title: "Speed Insight",
                text: app.insights.insight(
                    for: "speed",
                    context: speedContext,
                    fallback: FallbackInsight.speed(tester.result)),
                tint: Theme.green)
        }
        .onReceive(clock) { now = $0 }
    }

    // MARK: - Gauges

    private var gaugesCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                gauge(title: "DOWNLOAD",
                      mbps: displayDown,
                      color: Theme.blue,
                      icon: "arrow.down",
                      active: tester.phase == .download)
                    .frame(maxWidth: .infinity)
                Rectangle().fill(Theme.stroke).frame(width: 1).padding(.vertical, 16)
                gauge(title: "UPLOAD",
                      mbps: displayUp,
                      color: Theme.green,
                      icon: "arrow.up",
                      active: tester.phase == .upload)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 10)
        }
        .card(padding: 24)
    }

    private var displayDown: Double? {
        if tester.phase == .download { return tester.liveMbps }
        return tester.result?.downloadMbps
    }

    private var displayUp: Double? {
        if tester.phase == .upload { return tester.liveMbps }
        return tester.result?.uploadMbps
    }

    private func gauge(title: String, mbps: Double?, color: Color, icon: String, active: Bool) -> some View {
        VStack(spacing: 14) {
            ZStack {
                // Log-ish scale: 1000 Mbps fills the dial.
                ArcGauge(progress: gaugeProgress(mbps), color: color, lineWidth: 14, size: 170)
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(color))
                    Text(mbps.map { $0 >= 100 ? String(format: "%.0f", $0) : String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.default, value: mbps ?? 0)
                    Text("Mbps")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .kerning(1.5)
                .foregroundStyle(active ? color : Theme.textSecondary)
        }
    }

    private func gaugeProgress(_ mbps: Double?) -> Double {
        guard let mbps, mbps > 0 else { return 0 }
        // log scale from 1 to 2000 Mbps
        return min(1, max(0.02, log10(mbps) / log10(2000)))
    }

    // MARK: - Status / run button

    private var statusRow: some View {
        HStack {
            if tester.isRunning {
                ProgressView().controlSize(.small)
                Text(phaseLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            } else if let r = tester.result {
                Text("Tested \(Fmt.ago(r.date))")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("No test run yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if tester.isRunning {
                EmptyView()
            } else if tester.cooldownRemaining > 0 {
                Text("Wait \(tester.cooldownRemaining)s")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Button {
                    Task { await tester.run() }
                } label: {
                    Label("Run Speed Test", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Theme.blue))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 16)
        .animation(.default, value: tester.phase)
        // `now` keeps "Tested Xs ago" and the cooldown counting.
        .id(now.timeIntervalSince1970.rounded())
    }

    private var phaseLabel: String {
        switch tester.phase {
        case .latency: return "Measuring latency…"
        case .download: return "Testing download…"
        case .upload: return "Testing upload…"
        default: return ""
        }
    }

    // MARK: - Ratings

    private var latencyRating: String {
        guard let l = tester.result?.latencyMs ?? app.latencyMs else { return "" }
        switch l {
        case ..<20: return "Excellent"
        case ..<50: return "Good"
        case ..<100: return "Fair"
        default: return "High"
        }
    }

    private var dnsRating: String {
        guard let d = tester.result?.dnsMs else { return "" }
        switch d {
        case ..<20: return "Fast"
        case ..<80: return "OK"
        default: return "Slow"
        }
    }

    private var connectionRating: (String, String) {
        guard let r = tester.result else { return ("—", "run a test") }
        let score: String
        switch (r.downloadMbps, r.latencyMs ?? 999) {
        case (100..., ..<40): score = "Excellent"
        case (50..., ..<80): score = "Good"
        case (10..., _): score = "Fair"
        default: score = "Poor"
        }
        return (score, "Internet is \(score.lowercased())")
    }

    private var speedContext: String {
        guard let r = tester.result else { return "No speed test has been run yet." }
        return String(format: "Download %.1f Mbps, upload %.1f Mbps, latency %@ , DNS %@. Link rate %d Mbps, RSSI %d dBm.",
                      r.downloadMbps, r.uploadMbps,
                      r.latencyMs.map { Fmt.ms($0) } ?? "n/a",
                      r.dnsMs.map { Fmt.ms($0) } ?? "n/a",
                      Int(app.snap.txRate), app.snap.rssi)
    }
}
