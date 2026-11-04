import Foundation

/// 独立外观偏好，首次默认为图标同款。
enum MetronomeAppearance: String, CaseIterable, Identifiable, Codable {
    case icon, walnut, ivory, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: return "银白 · 图标同款"
        case .walnut: return "胡桃木"
        case .ivory: return "象牙白"
        case .graphite: return "曜石黑"
        }
    }

    var subtitle: String {
        switch self {
        case .icon: return "银白机身 · 冰蓝摆杆"
        case .walnut: return "温润木纹 · 黄铜盘面"
        case .ivory: return "奶油烤漆 · 复古金属"
        case .graphite: return "石墨磨砂 · 琥珀摆杆"
        }
    }

    /// 仅用于升级旧版绑定主题的数据。
    var legacyTimbre: Timbre {
        switch self {
        case .icon: return .crystalTick
        case .walnut: return .woodKnock
        case .ivory: return .feltHammer
        case .graphite: return .electroPulse
        }
    }

    static func forLegacyTimbre(_ raw: String) -> Self {
        switch Timbre.legacy(raw) {
        case .woodKnock: return .walnut
        case .feltHammer: return .ivory
        case .electroPulse: return .graphite
        default: return .icon
        }
    }

    static func loadLegacy(from defaults: UserDefaults) -> Self {
        defaults.string(forKey: "com.pianometronome.appearance.v1").flatMap(Self.init(rawValue:)) ?? .icon
    }
}
