import SwiftUI

// MARK: - Backdrop (the atmosphere the glass refracts)

struct GlassBackdrop: View {
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Theme.windowBG
                orb(Theme.orbA, diameter: w * 1.0)
                    .position(x: drift ? w * 0.12 : w * 0.32,
                              y: drift ? h * 0.05 : h * 0.22)
                orb(Theme.orbB, diameter: w * 0.9)
                    .position(x: drift ? w * 0.95 : w * 0.75,
                              y: drift ? h * 0.85 : h * 0.65)
                orb(Theme.orbC, diameter: w * 0.8)
                    .position(x: drift ? w * 0.75 : w * 0.5,
                              y: drift ? h * 0.15 : h * 0.4)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            // Slow drift so the frost visibly smears moving color.
            withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func orb(_ color: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, .clear],
                                 center: .center, startRadius: 0, endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
    }
}

// MARK: - Card chrome (frosted glass)

struct CardStyle: ViewModifier {
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(
                        // Light catching the top of the pane.
                        shape.fill(
                            LinearGradient(colors: [Theme.sheen, .clear],
                                           startPoint: .top, endPoint: .center)
                        )
                    )
                    .overlay(
                        shape.strokeBorder(
                            LinearGradient(colors: [Theme.glassEdgeTop, Theme.glassEdgeBottom],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    )
                    .shadow(color: Theme.cardShadow, radius: 14, y: 6)
            }
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
        VStack(alignment: .leading, spacing: 14) {
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
                    .font(.system(size: 22, weight: .bold, design: monospacedValue ? .monospaced : .default))
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.system(size: 15, weight: .bold))
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
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.opacity(0.09))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(tint.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: Theme.cardShadow, radius: 12, y: 5)
        }
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
                        .foregroundStyle(selection == option.0 ? Theme.inkContrast : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(selection == option.0 ? Theme.ink : Color.clear)
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
        VStack(alignment: .leading, spacing: 14) {
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
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
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
