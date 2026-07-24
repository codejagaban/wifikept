import SwiftUI

// MARK: - Backdrop (the atmosphere the glass refracts)

struct GlassBackdrop: View {
    var body: some View {
        Theme.windowBG.ignoresSafeArea()
    }
}

// MARK: - Card chrome (frosted glass)

struct CardStyle: ViewModifier {
    var padding: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View { modifier(CardStyle(padding: padding)) }
}

// MARK: - Metric card (icon + caps title, big value, small detail)

struct MetricCard: View {
    var icon: String
    var iconColor: Color
    var title: String
    var value: String
    var detail: String = ""
    var monospacedValue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(alignment: .lastTextBaseline) {
                Text(value)
                    .font(monospacedValue ? .mono(22, .bold) : .display(22, .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !detail.isEmpty {
                    Spacer(minLength: 8)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .card()
    }
}

// MARK: - Arc gauge (270° sweep, like the Signal / Speed dials)

struct ArcGauge: View {
    var progress: Double          // 0…1
    var color: Color
    var lineWidth: CGFloat = 12
    var size: CGFloat = 150

    @State private var shown = false

    private var clamped: Double { min(1, max(0, progress)) }
    private var display: Double { shown ? clamped : 0 }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Theme.track,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * display)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.smooth(duration: 0.45), value: display)
        }
        .frame(width: size, height: size)
        .onAppear {
            // Sweep in from zero when the tab appears.
            withAnimation(.smooth(duration: 0.9)) { shown = true }
        }
    }
}

// MARK: - Meter row (label, value, horizontal bar, caption)

struct MeterRow: View {
    var title: String
    var valueText: String
    var progress: Double
    var color: Color
    var caption: String

    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(valueText)
                    .font(.display(15, .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(color)
                        .frame(width: max(6, geo.size.width * min(1, max(0, progress)) * (shown ? 1 : 0)))
                        .animation(.smooth(duration: 0.5), value: progress)
                }
            }
            .frame(height: 5)
            .onAppear {
                withAnimation(.smooth(duration: 0.8)) { shown = true }
            }
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Insight box

struct InsightBox: View {
    var title: String
    var text: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 17))
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Section label

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(1.2)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pill segmented picker

struct PillPicker<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option in
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == option.0 ? Color.white : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(selection == option.0 ? Theme.blue : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.fillSubtle))
    }
}

// MARK: - Copyable value card (Details tab)

struct CopyCard: View {
    var icon: String
    var iconColor: Color
    var title: String
    var value: String?
    var trailing: String = ""

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let value, !value.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(copied ? Theme.green : Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy")
                }
            }
            HStack(alignment: .lastTextBaseline) {
                Text(value?.isEmpty == false ? value! : "—")
                    .font(.mono(17, .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !trailing.isEmpty {
                    Spacer(minLength: 8)
                    Text(trailing)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
