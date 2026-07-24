import SwiftUI
import AppKit

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

/// App palette. Every color is a dynamic NSColor that resolves against the
/// effective appearance, so the whole UI adapts to light/dark automatically.
enum Theme {
    private static func dyn(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    private static func dyn(light: UInt32, dark: UInt32) -> Color {
        dyn(light: NSColor(hex: light), dark: NSColor(hex: dark))
    }

    // Surfaces
    static let windowBG = dyn(light: 0xE9EDF3, dark: 0x000000)
    static let headerBG = dyn(light: 0xE7E9EE, dark: 0x000000)
    static let card = dyn(light: 0xFFFFFF, dark: 0x101012)
    /// Semi-transparent card used in the menu bar popover so the
    /// behind-window blur shows through the tiles.
    static let cardTranslucent = dyn(light: NSColor.white.withAlphaComponent(0.35),
                                     dark: NSColor(hex: 0x1A1A1D, alpha: 0.35))
    static let cardElevated = dyn(light: 0xFFFFFF, dark: 0x18181B)
    static let stroke = dyn(light: NSColor.black.withAlphaComponent(0.08),
                            dark: NSColor.white.withAlphaComponent(0.06))

    // Glass: backdrop color orbs, edge highlights, sheen and card shadows.
    // The orbs are deliberately saturated — frosted cards read as glass only
    // when there's visible color behind them to blur.
    static let orbA = dyn(light: NSColor(hex: 0x86AEFF, alpha: 0.60),
                          dark: NSColor(hex: 0x2E4070, alpha: 0.80))
    static let orbB = dyn(light: NSColor(hex: 0x7EDCD0, alpha: 0.55),
                          dark: NSColor(hex: 0x1D5B60, alpha: 0.65))
    static let orbC = dyn(light: NSColor(hex: 0xC9B8F5, alpha: 0.50),
                          dark: NSColor(hex: 0x45336E, alpha: 0.60))
    static let glassEdgeTop = dyn(light: NSColor.white.withAlphaComponent(0.95),
                                  dark: NSColor.white.withAlphaComponent(0.35))
    static let glassEdgeBottom = dyn(light: NSColor.white.withAlphaComponent(0.30),
                                     dark: NSColor.white.withAlphaComponent(0.08))
    static let sheen = dyn(light: NSColor.white.withAlphaComponent(0.35),
                           dark: NSColor.white.withAlphaComponent(0.10))
    static let cardShadow = dyn(light: NSColor.black.withAlphaComponent(0.13),
                                dark: NSColor.black.withAlphaComponent(0.50))

    // Neutral overlays (bars, pill containers, gauge tracks, gridlines)
    static let fillSubtle = dyn(light: NSColor.black.withAlphaComponent(0.05),
                                dark: NSColor.white.withAlphaComponent(0.06))
    static let fillSelected = dyn(light: NSColor.black.withAlphaComponent(0.10),
                                  dark: NSColor.white.withAlphaComponent(0.12))
    static let track = dyn(light: NSColor.black.withAlphaComponent(0.08),
                           dark: NSColor.white.withAlphaComponent(0.08))
    static let gridline = dyn(light: NSColor.black.withAlphaComponent(0.06),
                              dark: NSColor.white.withAlphaComponent(0.05))
    static let marker = dyn(light: NSColor.black.withAlphaComponent(0.35),
                            dark: NSColor.white.withAlphaComponent(0.30))

    // Text
    static let textPrimary = dyn(light: 0x1A1D24, dark: 0xF5F5F6)
    static let textSecondary = dyn(light: 0x5C6572, dark: 0x9FA1A6)
    static let textTertiary = dyn(light: 0x8B93A1, dark: 0x6A6C71)

    // Accents — light variants darkened enough to read as TEXT on light
    // surfaces (the bright system fills failed contrast there); dark
    // variants stay vivid where they work.
    static let green = dyn(light: 0x23B14E, dark: 0x32D74B)
    static let blue = dyn(light: 0x007AFF, dark: 0x0A84FF)
    static let orange = dyn(light: 0xE8710A, dark: 0xFF9F0A)
    static let purple = dyn(light: 0x9F4FC9, dark: 0xBF5AF2)
    static let pink = dyn(light: 0xE72652, dark: 0xFF375F)
    static let teal = dyn(light: 0x1E98A1, dark: 0x40C8E0)
    static let yellow = dyn(light: 0xBF8700, dark: 0xD4B845)
    static let red = dyn(light: 0xE3352B, dark: 0xFF453A)
    static let indigo = dyn(light: 0x5654DB, dark: 0x5E5CE6)

    /// Apple Intelligence-style gradient, used only on the AI glyph.
    static let aiGradient = LinearGradient(
        colors: [blue, purple, pink],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Font {
    /// JetBrains Mono (bundled) — identifiers where digit alignment matters
    /// (BSSID, MAC, IPs, dBm readouts).
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "JetBrainsMono-Bold"
        case .semibold: name = "JetBrainsMono-SemiBold"
        case .medium: name = "JetBrainsMono-Medium"
        default: name = "JetBrainsMono-Regular"
        }
        return .custom(name, size: size)
    }

    /// Bricolage Grotesque (bundled, 24pt optical cut) — the display face
    /// carrying big numbers and values.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "BricolageGrotesque-24ptBold"
        case .semibold: name = "BricolageGrotesque-24ptSemiBold"
        case .medium: name = "BricolageGrotesque-24ptMedium"
        default: name = "BricolageGrotesque-24pt"
        }
        return .custom(name, size: size)
    }
}

/// User-selectable appearance, stored in AppStorage("appearance").
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
