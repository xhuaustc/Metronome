import SwiftUI

/// 材质配色供主页和设置缩略图共用。
struct InstrumentPalette {
    let body: [Color]
    let face: [Color]
    let rod: [Color]
    let weight: [Color]
    let base: [Color]
    let trim: Color
    let ink: Color
    let metal: Color
    let cornerRadius: CGFloat
    let topInset: CGFloat
    let woodGrain: Bool
    let darkFace: Bool

    init(_ appearance: MetronomeAppearance) {
        switch appearance {
        case .icon:
            body = [0xF6F6F4, 0xB7BDC1, 0xE4E7E7, 0x959CA1].map(Color.init(hex:))
            face = [0x151B20, 0x303A42, 0x11171C].map(Color.init(hex:))
            rod = [0x0669B6, 0x72D6FF, 0x168EED].map(Color.init(hex:))
            weight = [0xA3E8FF, 0x259DF5, 0x0876DC, 0x03467D].map(Color.init(hex:))
            base = [0xDFE4E6, 0x8C969C].map(Color.init(hex:))
            trim = Color(hex: 0xE3E9EE); ink = Color(hex: 0xCEDAE3); metal = Color(hex: 0xAFBBC2)
            cornerRadius = 15; topInset = 0.29; woodGrain = false; darkFace = true
        case .walnut:
            body = [0x98613E, 0x50301F, 0x805034, 0x382318].map(Color.init(hex:))
            face = [0xE1C58E, 0xB39764, 0xDFCA9C].map(Color.init(hex:))
            rod = [0x4F504B, 0xF3EFE1, 0x777971].map(Color.init(hex:))
            weight = [0xF3D69D, 0xB28A4C, 0xE4C28A, 0x8A6534].map(Color.init(hex:))
            base = [0x543721, 0x251B13].map(Color.init(hex:))
            trim = Color(hex: 0xBF8C5C); ink = Color(hex: 0x49331E); metal = Color(hex: 0xD6BB85)
            cornerRadius = 3; topInset = 0.25; woodGrain = true; darkFace = false
        case .ivory:
            body = [0xFFF5DE, 0xBBAE95, 0xEEE0C4, 0xA7997F].map(Color.init(hex:))
            face = [0xF0E6CC, 0xDFD0AE, 0xF6ECD2].map(Color.init(hex:))
            rod = [0x4C3D2B, 0xC1A36A, 0x6E5632].map(Color.init(hex:))
            weight = [0xEED6A3, 0xA78149, 0xDCC18C, 0x72552E].map(Color.init(hex:))
            base = [0x9B825C, 0x574733].map(Color.init(hex:))
            trim = Color(hex: 0xC9AD77); ink = Color(hex: 0x584835); metal = Color(hex: 0xBA9A60)
            cornerRadius = 10; topInset = 0.27; woodGrain = false; darkFace = false
        case .graphite:
            body = [0x51565D, 0x1E2228, 0x3D444C, 0x161A1F].map(Color.init(hex:))
            face = [0x151A20, 0x262D34, 0x10151A].map(Color.init(hex:))
            rod = [0x9F5618, 0xF6CF83, 0xD88A32].map(Color.init(hex:))
            weight = [0xFFE2A5, 0xE8A248, 0xBD722A, 0x784016].map(Color.init(hex:))
            base = [0x3D444D, 0x14181E].map(Color.init(hex:))
            trim = Color(hex: 0x69757F); ink = Color(hex: 0xCCD5DC); metal = Color(hex: 0x8F9BA4)
            cornerRadius = 19; topInset = 0.28; woodGrain = false; darkFace = true
        }
    }
}
