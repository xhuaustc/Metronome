import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0E0E10)
    static let surface = Color(hex: 0x1A1A1E)
    static let textPrimary = Color(hex: 0xF5F5F7)
    static let textSecondary = Color(hex: 0x9A9AA0)
    static let textTertiary = Color(hex: 0x6E6E75)
    static let accent = Color(hex: 0x4DA3FF)
    static let accentSoft = Color(hex: 0x2C5F91)
    static let warning = Color(hex: 0xE8695C)
    static let dotIdle = Color(hex: 0x3A3A3E)
    static let stroke = Color(hex: 0x33333A)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
