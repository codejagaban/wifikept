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

    // Ink: the single data/interaction color — near-black on light,
    // near-white on dark. The minimal palette's workhorse.
    static let ink = dyn(light: 0x14161B, dark: 0xF2F3F5)
    static let inkContrast = dyn(light: 0xFFFFFF, dark: 0x14161B)
    /// Secondary chart series (upload, noise) — quiet gray next to ink.
    static let seriesSecondary = dyn(light: 0x9AA0AA, dark: 0x6C7280)

    // Surfaces
    static let windowBG = dyn(light: 0xEDEEF1, dark: 0x121419)
    static let headerBG = dyn(light: 0xE7E9EE, dark: 0x0D0F13)
    static let card = dyn(light: 0xFFFFFF, dark: 0x1C202A)
    static let cardElevated = dyn(light: 0xFFFFFF, dark: 0x222735)
    static let stroke = dyn(light: NSColor.black.withAlphaComponent(0.08),
                            dark: NSColor.white.withAlphaComponent(0.06))

    // Glass: backdrop color orbs, edge highlights, sheen and card shadows.
    // The orbs are deliberately saturated — frosted cards read as glass only
    // when there's visible color behind them to blur.
    static let orbA = dyn(light: NSColor.white.withAlphaComponent(0.90),
                          dark: NSColor(hex: 0x272B34, alpha: 0.90))
    static let orbB = dyn(light: NSColor(hex: 0xD6DBE3, alpha: 0.70),
                          dark: NSColor(hex: 0x191C22, alpha: 0.85))
    static let orbC = dyn(light: NSColor(hex: 0xF2F3F6, alpha: 0.65),
                          dark: NSColor(hex: 0x2D3139, alpha: 0.70))
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
    static let textPrimary = dyn(light: 0x1A1D24, dark: 0xF2F4F8)
    static let textSecondary = dyn(light: 0x5C6572, dark: 0x9AA3B2)
    static let textTertiary = dyn(light: 0x8B93A1, dark: 0x687080)

    // Status colors — the ONLY real color in the app, reserved for meaning
    // (signal quality, warnings). Slightly muted to sit in the minimal palette.
    static let green = dyn(light: 0x2FA455, dark: 0x46BE6B)
    static let yellow = dyn(light: 0xC29A2A, dark: 0xD4B04A)
    static let red = dyn(light: 0xDE4A40, dark: 0xE8625A)

    // Legacy accent names, retained so nothing breaks — all resolve to
    // neutral ink/gray in the minimal palette.
    static let blue = ink
    static let orange = ink
    static let purple = ink
    static let pink = ink
    static let teal = ink
    static let indigo = ink
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
