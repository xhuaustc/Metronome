import Foundation

/// 独立于外观的机械敲击音色。
enum Timbre: String, CaseIterable, Codable {
    case crystalTick, woodKnock, feltHammer, electroPulse

    var displayName: String {
        switch self {
        case .crystalTick: return "清脆机械敲击"
        case .woodKnock: return "木壳机械敲击"
        case .feltHammer: return "柔和机械敲击"
        case .electroPulse: return "紧致机械敲击"
        }
    }

    var baseFrequency: Double {
        switch self {
        case .crystalTick: return 1650
        case .woodKnock: return 1250
        case .feltHammer: return 950
        case .electroPulse: return 1850
        }
    }

    var decay: Double {
        switch self {
        case .crystalTick: return 230
        case .woodKnock: return 260
        case .feltHammer: return 210
        case .electroPulse: return 310
        }
    }

    var noiseMix: Double {
        switch self {
        case .crystalTick: return 0.50
        case .woodKnock: return 0.65
        case .feltHammer: return 0.25
        case .electroPulse: return 0.55
        }
    }

    /// 均短于 400 BPM 四等分的 37.5ms 间隔。
    var duration: Double {
        switch self {
        case .crystalTick: return 0.034
        case .woodKnock: return 0.034
        case .feltHammer: return 0.036
        case .electroPulse: return 0.030
        }
    }

    var attack: Double {
        switch self {
        case .crystalTick: return 0.00025
        case .woodKnock, .electroPulse: return 0.0002
        case .feltHammer: return 0.0005
        }
    }

    /// 仅用于迁移旧收藏的三种独立音色。
    static func legacy(_ raw: String) -> Self? {
        switch raw {
        case "woodClick", "woodblock": return .woodKnock
        case "beep": return .crystalTick
        default: return Self(rawValue: raw)
        }
    }
}
