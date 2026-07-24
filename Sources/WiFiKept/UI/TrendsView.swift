import SwiftUI
import Charts

enum TrendMetric: String, CaseIterable, Identifiable {
    case signal = "Signal"
    case speed = "Speed"
    case link = "Link"
    case latency = "Latency"
    case noiseSNR = "Noise & SNR"
    case throughput = "Throughput"
    case channel = "Channel"
    var id: String { rawValue }
}

enum TrendRange: String, CaseIterable, Identifiable {
    case h1 = "1H"
    case h6 = "6H"
    case d1 = "1D"
    case d7 = "7D"
    case all = "All"
    var id: String { rawValue }
    var hours: Double? {
        switch self {
        case .h1: return 1
        case .h6: return 6
        case .d1: return 24
        case .d7: return 168
        case .all: return nil
        }
    }
}

struct TrendsView: View {
    @EnvironmentObject var app: AppState
    @State private var metric: TrendMetric = .signal
    @State private var range: TrendRange = .h6
    @State private var rows: [TrendRow] = []
    @State private var speedRows: [SpeedRow] = []
    @State private var hoverDate: Date?

    private let reload = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 18) {
                metricPicker
                chart
                    .frame(height: 300)
                HStack {
                    Spacer()
                    PillPicker(options: TrendRange.allCases.map { ($0, $0.rawValue) }, selection: $range)
                    Spacer()
                }
                HStack {
                    Text(metric == .speed ? "\(speedRows.count) tests" : "\(rows.count) samples")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Text("Hover to inspect")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .card(padding: 20)

            statsRow

            InsightBox(
                title: "Trend Insight",
                text: app.insights.insight(
                    for: "trends-\(metric.rawValue)-\(range.rawValue)",
                    context: trendContext,
                    fallback: FallbackInsight.trends(rows: rows)),
                tint: Theme.purple)
        }
        .onAppear(perform: load)
        .onChange(of: range) { load() }
        .onReceive(reload) { _ in load() }
    }

    private func load() {
        if let h = range.hours {
            rows = downsample(app.trendRows(hours: h))
        } else {
            rows = downsample(app.allTrendRows())
        }
        speedRows = app.speedRows(hours: range.hours)
    }

    /// Cap what the chart draws so long ranges stay fluid.
    private func downsample(_ input: [TrendRow], to target: Int = 700) -> [TrendRow] {
        guard input.count > target else { return input }
        let stride = Double(input.count) / Double(target)
        return (0..<target).map { input[Int(Double($0) * stride)] }
    }

    private var metricPicker: some View {
        HStack(spacing: 2) {
            ForEach(TrendMetric.allCases) { m in
                Button {
                    metric = m
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(metric == m ? .white : Theme.textSecondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(metric == m ? Theme.blue : Color.clear))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.fillSubtle))
    }

    // MARK: - Chart

    @ViewBuilder
    private var chart: some View {
        switch metric {
        case .signal:
            lineChart(values: rows.map { ($0.ts, Double($0.rssi)) }, color: Theme.blue,
                      unit: "dBm", domain: -100...0)
        case .speed:
            speedChart
        case .link:
            lineChart(values: rows.map { ($0.ts, $0.txRate) }, color: Theme.green, unit: "Mbps", domain: nil)
        case .latency:
            lineChart(values: rows.compactMap { r in r.latency.map { (r.ts, $0) } },
                      color: Theme.orange, unit: "ms", domain: nil)
        case .noiseSNR:
            noiseChart
        case .throughput:
            throughputChart
        case .channel:
            channelChart
        }
    }

    private func lineChart(values: [(Date, Double)], color: Color, unit: String,
                           domain: ClosedRange<Double>?) -> some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                LineMark(x: .value("Time", v.0), y: .value(unit, v.1))
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("Time", v.0), y: .value(unit, v.1))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.25), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
            }
            if let hoverDate, let nearest = nearestValue(in: values, to: hoverDate) {
                RuleMark(x: .value("Time", nearest.0))
                    .foregroundStyle(Theme.marker)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                PointMark(x: .value("Time", nearest.0), y: .value(unit, nearest.1))
                    .foregroundStyle(color)
                    .annotation(position: .top) {
                        Text("\(Int(nearest.1)) \(unit)")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.cardElevated))
                    }
            }
        }
        .modifier(TrendChartStyle(domain: domain))
        .chartXSelection(value: $hoverDate)
    }

    private var speedChart: some View {
        Chart {
            ForEach(Array(speedRows.enumerated()), id: \.offset) { _, r in
                LineMark(x: .value("Time", r.ts), y: .value("Mbps", r.down),
                         series: .value("Series", "Down"))
                    .foregroundStyle(Theme.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
                    .symbol { Circle().fill(Theme.blue).frame(width: 6, height: 6) }
                LineMark(x: .value("Time", r.ts), y: .value("Mbps", r.up),
                         series: .value("Series", "Up"))
                    .foregroundStyle(Theme.green)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
                    .symbol { Circle().fill(Theme.green).frame(width: 6, height: 6) }
            }
        }
        .modifier(TrendChartStyle(domain: nil))
        .chartForegroundStyleScale(["Down": Theme.blue, "Up": Theme.green])
        .overlay {
            if speedRows.isEmpty {
                Text("No speed tests in this range yet — run one in the Speed tab, or turn on automatic tests in Settings.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
    }

    private var noiseChart: some View {
        Chart {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                LineMark(x: .value("Time", r.ts), y: .value("dBm", Double(r.rssi)),
                         series: .value("Series", "Signal"))
                    .foregroundStyle(Theme.blue)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", r.ts), y: .value("dBm", Double(r.noise)),
                         series: .value("Series", "Noise"))
                    .foregroundStyle(Theme.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .interpolationMethod(.monotone)
            }
        }
        .modifier(TrendChartStyle(domain: -100...0))
        .chartForegroundStyleScale(["Signal": Theme.blue, "Noise": Theme.orange])
    }

    private var throughputChart: some View {
        Chart {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                LineMark(x: .value("Time", r.ts), y: .value("Mbps", r.rxBps * 8 / 1_000_000),
                         series: .value("Series", "Down"))
                    .foregroundStyle(Theme.blue)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", r.ts), y: .value("Mbps", r.txBps * 8 / 1_000_000),
                         series: .value("Series", "Up"))
                    .foregroundStyle(Theme.green)
                    .interpolationMethod(.monotone)
            }
        }
        .modifier(TrendChartStyle(domain: nil))
        .chartForegroundStyleScale(["Down": Theme.blue, "Up": Theme.green])
    }

    private var channelChart: some View {
        Chart {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                LineMark(x: .value("Time", r.ts), y: .value("Channel", Double(r.channel)))
                    .foregroundStyle(Theme.teal)
                    .interpolationMethod(.stepEnd)
            }
        }
        .modifier(TrendChartStyle(domain: nil))
    }

    private func nearestValue(in values: [(Date, Double)], to date: Date) -> (Date, Double)? {
        values.min { abs($0.0.timeIntervalSince(date)) < abs($1.0.timeIntervalSince(date)) }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 0) {
            ForEach(stats, id: \.0) { stat in
                VStack(spacing: 4) {
                    Text(stat.1)
                        .font(.display(19, .bold))
                        .foregroundStyle(stat.2)
                    Text(stat.0)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                if stat.0 != stats.last?.0 {
                    Rectangle().fill(Theme.stroke).frame(width: 1, height: 36)
                }
            }
        }
        .card(padding: 18)
    }

    private var stats: [(String, String, Color)] {
        if metric == .speed {
            guard !speedRows.isEmpty else { return [("No speed tests yet", "—", Theme.textSecondary)] }
            let downs = speedRows.map(\.down)
            let ups = speedRows.map(\.up)
            return [
                ("Avg Down", Fmt.bitsPerSec(downs.reduce(0, +) / Double(downs.count) * 1_000_000), Theme.blue),
                ("Best Down", Fmt.bitsPerSec((downs.max() ?? 0) * 1_000_000), Theme.blue),
                ("Avg Up", Fmt.bitsPerSec(ups.reduce(0, +) / Double(ups.count) * 1_000_000), Theme.green),
                ("Tests", "\(speedRows.count)", Theme.textSecondary),
            ]
        }
        guard !rows.isEmpty else { return [("No data yet", "—", Theme.textSecondary)] }
        switch metric {
        case .signal, .noiseSNR:
            let rssis = rows.map(\.rssi)
            let noises = rows.map(\.noise)
            let snrs = rows.map(\.rssi).enumerated().map { rows[$0.offset].rssi - rows[$0.offset].noise }
            return [
                ("Avg Signal", "\(rssis.reduce(0, +) / rssis.count) dBm", Theme.blue),
                ("Avg Noise", "\(noises.reduce(0, +) / noises.count) dBm", Theme.orange),
                ("Avg SNR", "\(snrs.reduce(0, +) / snrs.count) dB", Theme.green),
                ("Best SNR", "\(snrs.max() ?? 0) dB", Theme.green),
            ]
        case .link:
            let rates = rows.map(\.txRate)
            return [
                ("Avg Link", "\(Int(rates.reduce(0, +) / Double(rates.count))) Mbps", Theme.green),
                ("Min", "\(Int(rates.min() ?? 0)) Mbps", Theme.orange),
                ("Max", "\(Int(rates.max() ?? 0)) Mbps", Theme.blue),
            ]
        case .latency:
            let lats = rows.compactMap(\.latency)
            guard !lats.isEmpty else { return [("No latency samples yet", "—", Theme.textSecondary)] }
            return [
                ("Avg Latency", Fmt.ms(lats.reduce(0, +) / Double(lats.count)), Theme.orange),
                ("Best", Fmt.ms(lats.min() ?? 0), Theme.green),
                ("Worst", Fmt.ms(lats.max() ?? 0), Theme.red),
            ]
        case .throughput:
            let rx = rows.map(\.rxBps)
            let tx = rows.map(\.txBps)
            return [
                ("Avg Down", Fmt.bitsPerSec(rx.reduce(0, +) / Double(rx.count) * 8), Theme.blue),
                ("Avg Up", Fmt.bitsPerSec(tx.reduce(0, +) / Double(tx.count) * 8), Theme.green),
                ("Peak Down", Fmt.bitsPerSec((rx.max() ?? 0) * 8), Theme.blue),
                ("Peak Up", Fmt.bitsPerSec((tx.max() ?? 0) * 8), Theme.green),
            ]
        case .speed:
            return [] // handled above
        case .channel:
            let channels = Set(rows.map(\.channel))
            return [
                ("Channels used", "\(channels.count)", Theme.teal),
                ("Current", "Ch \(app.snap.channel)", Theme.blue),
            ]
        }
    }

    private var trendContext: String {
        guard !rows.isEmpty else { return "No trend data yet." }
        let rssis = rows.map(\.rssi)
        let avgRssi = rssis.reduce(0, +) / rssis.count
        let snrs = rows.map { $0.rssi - $0.noise }
        let avgSnr = snrs.reduce(0, +) / snrs.count
        return "Over the selected \(range.rawValue) window (\(rows.count) samples): average signal \(avgRssi) dBm, average SNR \(avgSnr) dB, best SNR \(snrs.max() ?? 0) dB. Current metric shown: \(metric.rawValue)."
    }
}

private struct TrendChartStyle: ViewModifier {
    var domain: ClosedRange<Double>?

    func body(content: Content) -> some View {
        let styled = content
            .chartXAxis {
                AxisMarks {
                    AxisGridLine().foregroundStyle(Theme.gridline)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks {
                    AxisGridLine().foregroundStyle(Theme.gridline)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .chartLegend(position: .top, alignment: .trailing)
        if let domain {
            styled.chartYScale(domain: domain)
        } else {
            styled
        }
    }
}
