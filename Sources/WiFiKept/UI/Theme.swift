import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Theme {
    static let windowBG = Color(hex: 0x14161C)
    static let headerBG = Color(hex: 0x0D0F13)
    static let card = Color(hex: 0x1C202A)
    static let cardElevated = Color(hex: 0x222735)
    static let stroke = Color.white.opacity(0.06)

    static let textPrimary = Color(hex: 0xF2F4F8)
    static let textSecondary = Color(hex: 0x9AA3B2)
    static let textTertiary = Color(hex: 0x687080)

    static let green = Color(hex: 0x32D74B)
    static let blue = Color(hex: 0x0A84FF)
    static let orange = Color(hex: 0xFF9F0A)
    static let purple = Color(hex: 0xBF5AF2)
    static let pink = Color(hex: 0xFF375F)
    static let teal = Color(hex: 0x40C8E0)
    static let yellow = Color(hex: 0xFFD60A)
    static let red = Color(hex: 0xFF453A)
    static let indigo = Color(hex: 0x5E5CE6)
}
