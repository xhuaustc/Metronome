import SwiftUI

enum Theme {
    static let background = Color(hex: 0x101316)
    static let surface = Color(hex: 0x242B31)
    static let panel = Color(hex: 0x181E23)
    static let textPrimary = Color(hex: 0xF0F4F7)
    static let textSecondary = Color(hex: 0xAFBEC9)
    static let textTertiary = Color(hex: 0x8899A6)
    static let accent = Color(hex: 0x59BCFF)
    static let accentSoft = Color(hex: 0x257BB5)
    static let warning = accent
    static let dotIdle = Color(hex: 0x46535E)
    static let stroke = Color(hex: 0x34414B)
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
