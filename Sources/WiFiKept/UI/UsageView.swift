import SwiftUI
import Charts

struct UsageView: View {
    @EnvironmentObject var app: AppState
    @State private var range: UsageRange = .week
    @State private var totals = UsageTotals()
    @State private var series: [UsageBucket] = []
    @State private var hoverDate: Date?

    var body: some View {
        VStack(spacing: 16) {
            totalsRow
            chartCard
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
    }

    // MARK: - Totals

    private var totalsRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            totalCard(title: "Today", pair: totals.today, color: Theme.blue)
            totalCard(title: "This Week", pair: totals.week, color: Theme.teal)
            totalCard(title: "This Month", pair: totals.month, color: Theme.purple)
            totalCard(title: "All Time", pair: totals.allTime, color: Theme.ink)
        }
    }

    private func totalCard(title: String, pair: (rx: Int64, tx: Int64), color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(Theme.textSecondary)
            Text(Fmt.bytes(pair.rx + pair.tx))
                .font(.system(size: 24, weight: .bold))
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
        .card(padding: 16)
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Data moved")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
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
                        .foregroundStyle(Theme.seriesSecondary)
                }
                .font(.system(size: 11))
            }
        }
        .card(padding: 20)
    }

    private var chart: some View {
        Chart {
            ForEach(series) { b in
                BarMark(x: .value("Date", b.date, unit: barUnit),
                        y: .value("Bytes", Double(b.rx)))
                    .foregroundStyle(Theme.blue)
                    .cornerRadius(3)
                BarMark(x: .value("Date", b.date, unit: barUnit),
                        y: .value("Bytes", Double(b.tx)))
                    .foregroundStyle(Theme.seriesSecondary)
                    .cornerRadius(3)
            }
            if let hoverDate, let bucket = nearestBucket(to: hoverDate) {
                RuleMark(x: .value("Date", bucket.date, unit: barUnit))
                    .foregroundStyle(Theme.marker)
                    .annotation(position: .top) {
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

    // MARK: - Live

    private var liveRow: some View {
        HStack(spacing: 14) {
            MetricCard(icon: "arrow.down.circle.fill", iconColor: Theme.blue,
                       title: "Receiving", value: Fmt.bytesPerSec(app.rxBps),
                       detail: "live")
            MetricCard(icon: "arrow.up.circle.fill", iconColor: Theme.textSecondary,
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
