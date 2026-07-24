import SwiftUI
import Charts

enum UsageChartStyle: String, CaseIterable, Identifiable {
    case bar
    case line
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .bar: return "chart.bar.fill"
        case .line: return "chart.xyaxis.line"
        }
    }
    var help: String {
        switch self {
        case .bar: return "Bar chart"
        case .line: return "Line graph"
        }
    }
}

struct UsageView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("usage.chartStyle") private var chartStyleRaw = UsageChartStyle.bar.rawValue
    @AppStorage("budget.gb") private var budgetGB = 0.0
    @State private var range: UsageRange = .week
    @State private var totals = UsageTotals()
    @State private var series: [UsageBucket] = []
    @State private var topApps: [(app: String, rx: Int64, tx: Int64)] = []
    @State private var networks: [(network: String?, rx: Int64, tx: Int64)] = []
    @State private var hoverDate: Date?

    private var chartStyle: UsageChartStyle {
        UsageChartStyle(rawValue: chartStyleRaw) ?? .bar
    }

    var body: some View {
        VStack(spacing: 16) {
            totalsRow
            if budgetGB > 0 {
                budgetBar
            }
            chartCard
            liveTalkersCard
            topAppsCard
            networksCard
            liveRow
            InsightBox(
                title: "Usage Insight",
                text: app.insights.insight(
                    for: "usage",
                    context: usageContext,
                    fallback: FallbackInsight.usage(
                        today: totals.today.rx + totals.today.tx,
                        week: totals.week.rx + totals.week.tx,
                        month: totals.month.rx + totals.month.tx)),
                tint: Theme.teal)
        }
        .onAppear(perform: load)
        .onChange(of: range) { load() }
        .onChange(of: app.usageStamp) { load() }
    }

    private func load() {
        totals = app.usageTotals()
        series = app.usageSeries(range: range)
        topApps = app.topApps(range: range)
        networks = app.networkTotals(range: range)
    }

    // MARK: - Totals

    private var totalsRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            totalCard(title: "Today", pair: totals.today, color: Theme.blue)
            totalCard(title: "This Week", pair: totals.week, color: Theme.teal)
            totalCard(title: "This Month", pair: totals.month, color: Theme.purple)
            totalCard(title: "All Time", pair: totals.allTime, color: Theme.green)
        }
    }

    private func totalCard(title: String, pair: (rx: Int64, tx: Int64), color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(Theme.textSecondary)
            Text(Fmt.bytes(pair.rx + pair.tx))
                .font(.display(24, .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 10) {
                Label(Fmt.bytes(pair.rx), systemImage: "arrow.down")
                Label(Fmt.bytes(pair.tx), systemImage: "arrow.up")
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)
            .labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20)
    }

    // MARK: - Budget

    private var budgetBar: some View {
        let used = Double(totals.month.rx + totals.month.tx)
        let limit = budgetGB * 1_000_000_000
        let fraction = limit > 0 ? used / limit : 0
        let color: Color = fraction >= 1 ? Theme.red : fraction >= 0.8 ? Theme.yellow : Theme.green
        return HStack(spacing: 14) {
            Text("MONTHLY BUDGET")
                .font(.system(size: 11, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(Theme.textSecondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(color)
                        .frame(width: max(4, geo.size.width * min(1, fraction)))
                        .animation(.smooth(duration: 0.5), value: fraction)
                }
            }
            .frame(height: 6)
            Text("\(Int((fraction * 100).rounded()))% of \(budgetGB >= 1000 ? "1 TB" : "\(Int(budgetGB)) GB")")
                .font(.display(13, .semibold))
                .foregroundStyle(color)
                .layoutPriority(1)
        }
        .card(padding: 16)
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Text("Data moved")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                stylePicker
                PillPicker(options: UsageRange.allCases.map { ($0, $0.rawValue) }, selection: $range)
            }
            if series.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Usage will appear here as WiFiKept records your connection.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                chart
                    .frame(height: 240)
            }
            HStack {
                if let since = totals.since {
                    Text("Tracking since \(since.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                HStack(spacing: 14) {
                    Label("Download", systemImage: "square.fill")
                        .foregroundStyle(Theme.blue)
                    Label("Upload", systemImage: "square.fill")
                        .foregroundStyle(Theme.green)
                }
                .font(.system(size: 11))
            }
        }
        .card(padding: 20)
    }

    private var stylePicker: some View {
        HStack(spacing: 2) {
            ForEach(UsageChartStyle.allCases) { style in
                Button {
                    withAnimation(.smooth(duration: 0.3)) { chartStyleRaw = style.rawValue }
                } label: {
                    Image(systemName: style.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(chartStyle == style ? Theme.textPrimary : Theme.textTertiary)
                        .frame(width: 30, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(chartStyle == style ? Theme.fillSelected : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(style.help)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.fillSubtle))
    }

    private var chart: some View {
        Chart {
            ForEach(series) { b in
                switch chartStyle {
                case .bar:
                    BarMark(x: .value("Date", b.date, unit: barUnit),
                            y: .value("Bytes", Double(b.rx)))
                        .foregroundStyle(Theme.blue)
                        .cornerRadius(3)
                    BarMark(x: .value("Date", b.date, unit: barUnit),
                            y: .value("Bytes", Double(b.tx)))
                        .foregroundStyle(Theme.green)
                        .cornerRadius(3)
                case .line:
                    AreaMark(x: .value("Date", b.date, unit: barUnit),
                             y: .value("Bytes", Double(b.rx)),
                             series: .value("Series", "Down"))
                        .foregroundStyle(LinearGradient(colors: [Theme.blue.opacity(0.30), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", b.date, unit: barUnit),
                             y: .value("Bytes", Double(b.rx)),
                             series: .value("Series", "Down"))
                        .foregroundStyle(Theme.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                        .symbol {
                            Circle().fill(Theme.blue).frame(width: 6, height: 6)
                        }
                    LineMark(x: .value("Date", b.date, unit: barUnit),
                             y: .value("Bytes", Double(b.tx)),
                             series: .value("Series", "Up"))
                        .foregroundStyle(Theme.green)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                        .symbol {
                            Circle().fill(Theme.green).frame(width: 6, height: 6)
                        }
                }
            }
            if let hoverDate, let bucket = nearestBucket(to: hoverDate) {
                RuleMark(x: .value("Date", bucket.date, unit: barUnit))
                    .foregroundStyle(Theme.marker)
                    .annotation(position: .top, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(bucketLabel(bucket.date))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("↓ \(Fmt.bytes(bucket.rx))   ↑ \(Fmt.bytes(bucket.tx))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardElevated))
                    }
            }
        }
        .chartXSelection(value: $hoverDate)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks {
                AxisGridLine().foregroundStyle(Theme.gridline)
                AxisValueLabel().foregroundStyle(Theme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Theme.gridline)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(Fmt.bytes(Int64(v)))
                    }
                }
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .chartLegend(.hidden)
    }

    /// Pin the Y axis to the data so the hover tooltip doesn't rescale
    /// the chart when it appears.
    private var yMax: Double {
        let peak: Int64
        switch chartStyle {
        case .bar: peak = series.map { $0.rx + $0.tx }.max() ?? 0
        case .line: peak = series.map { max($0.rx, $0.tx) }.max() ?? 0
        }
        return max(Double(peak) * 1.15, 1)
    }

    /// Pin the axis to the full selected range so sparse data doesn't
    /// stretch a single bucket across the whole chart.
    private var xDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let now = Date()
        switch range {
        case .day:
            return now.addingTimeInterval(-86_400)...now
        case .week:
            return cal.startOfDay(for: now.addingTimeInterval(-6 * 86_400))...now.addingTimeInterval(3600)
        case .month:
            return cal.startOfDay(for: now.addingTimeInterval(-29 * 86_400))...now.addingTimeInterval(3600)
        case .year:
            let start = cal.date(byAdding: .month, value: -11,
                                 to: cal.dateInterval(of: .month, for: now)?.start ?? now) ?? now
            return start...now.addingTimeInterval(3600)
        case .all:
            let first = totals.since ?? now.addingTimeInterval(-86_400)
            let start = cal.dateInterval(of: .month, for: first)?.start ?? first
            return start...now.addingTimeInterval(3600)
        }
    }

    private var barUnit: Calendar.Component {
        switch range {
        case .day: return .hour
        case .week, .month: return .day
        case .year, .all: return .month
        }
    }

    private func nearestBucket(to date: Date) -> UsageBucket? {
        series.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func bucketLabel(_ date: Date) -> String {
        switch barUnit {
        case .hour: return date.formatted(date: .omitted, time: .shortened)
        case .day: return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        default: return date.formatted(.dateTime.month(.wide).year())
        }
    }

    // MARK: - Live talkers

    private var liveTalkersCard: some View {
        let talkers = app.liveTalkers.filter { $0.rxBps + $0.txBps >= 200 }.prefix(5)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("USING DATA RIGHT NOW")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Circle().fill(Theme.green).frame(width: 7, height: 7)
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(Theme.textTertiary)
            }
            if talkers.isEmpty {
                Text("Quiet right now — nothing is moving meaningful data.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(talkers), id: \.app) { t in
                        HStack(spacing: 12) {
                            appIcon(for: t.app)
                            Text(t.app)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text("↓ \(Fmt.bytesPerSec(t.rxBps))")
                                .font(.mono(12, .medium))
                                .foregroundStyle(Theme.blue)
                            Text("↑ \(Fmt.bytesPerSec(t.txBps))")
                                .font(.mono(12, .medium))
                                .foregroundStyle(Theme.green)
                        }
                    }
                }
                .animation(.smooth(duration: 0.4), value: talkers.map(\.app))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - By network

    private var networksCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("BY NETWORK")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(range.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            if networks.isEmpty {
                Text("Network attribution starts with the next minute of tracking.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(networks.enumerated()), id: \.offset) { _, entry in
                        networkRow(entry: entry,
                                   peak: networks.first.map { $0.rx + $0.tx } ?? 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func networkRow(entry: (network: String?, rx: Int64, tx: Int64), peak: Int64) -> some View {
        let total = entry.rx + entry.tx
        let share = peak > 0 ? Double(total) / Double(peak) : 0
        let name = entry.network ?? "Unattributed (earlier or app closed)"
        return HStack(spacing: 12) {
            Image(systemName: entry.network == nil ? "clock.arrow.circlepath" : "wifi")
                .font(.system(size: 13))
                .foregroundStyle(entry.network == nil ? Theme.textTertiary : Theme.teal)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(entry.network == nil ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule().fill(Theme.teal)
                            .frame(width: max(3, geo.size.width * share))
                    }
                }
                .frame(height: 3)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.bytes(total))
                    .font(.display(14, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("↓ \(Fmt.bytes(entry.rx))  ↑ \(Fmt.bytes(entry.tx))")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - Where your data goes

    private var topAppsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("WHERE YOUR DATA GOES")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("Top \(min(10, max(topApps.count, 1))) · \(range.rawValue)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            if topApps.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Watching per-app traffic — the first entries appear within a minute.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(topApps.enumerated()), id: \.element.app) { index, entry in
                        appRow(rank: index + 1, entry: entry,
                               peak: topApps.first.map { $0.rx + $0.tx } ?? 1)
                    }
                }
            }
            Text("Attributed per app while WiFiKept is running, from macOS network statistics. Helper processes are rolled into their parent app.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func appRow(rank: Int, entry: (app: String, rx: Int64, tx: Int64), peak: Int64) -> some View {
        let total = entry.rx + entry.tx
        let share = peak > 0 ? Double(total) / Double(peak) : 0
        return HStack(spacing: 12) {
            Text("\(rank)")
                .font(.mono(11, .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 18, alignment: .trailing)
            appIcon(for: entry.app)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.app)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule().fill(Theme.blue)
                            .frame(width: max(3, geo.size.width * share))
                    }
                }
                .frame(height: 3)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.bytes(total))
                    .font(.display(14, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("↓ \(Fmt.bytes(entry.rx))  ↑ \(Fmt.bytes(entry.tx))")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func appIcon(for name: String) -> some View {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }),
           let icon = running.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 24, height: 24)
        } else if FileManager.default.fileExists(atPath: "/Applications/\(name).app") {
            Image(nsImage: NSWorkspace.shared.icon(forFile: "/Applications/\(name).app"))
                .resizable()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fillSubtle))
        }
    }

    // MARK: - Live

    private var liveRow: some View {
        HStack(spacing: 14) {
            MetricCard(icon: "arrow.down.circle.fill", iconColor: Theme.blue,
                       title: "Receiving", value: Fmt.bytesPerSec(app.rxBps),
                       detail: "live")
            MetricCard(icon: "arrow.up.circle.fill", iconColor: Theme.green,
                       title: "Sending", value: Fmt.bytesPerSec(app.txBps),
                       detail: "live")
            MetricCard(icon: "internaldrive.fill", iconColor: Theme.purple,
                       title: "Coverage", value: "All interfaces",
                       detail: "Wi-Fi, Ethernet & adapters")
        }
    }

    private var usageContext: String {
        let t = totals
        return "Wi-Fi data usage — today: \(Fmt.bytes(t.today.rx)) down / \(Fmt.bytes(t.today.tx)) up; this week: \(Fmt.bytes(t.week.rx)) down / \(Fmt.bytes(t.week.tx)) up; this month: \(Fmt.bytes(t.month.rx)) down / \(Fmt.bytes(t.month.tx)) up; all time: \(Fmt.bytes(t.allTime.rx + t.allTime.tx)) total."
    }
}
