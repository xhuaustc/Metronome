import Foundation

/// V1 的三种音色。参数是合成用的声学描述，不含任何播放逻辑，因此可放在 Core 层。
enum Timbre: String, CaseIterable, Identifiable, Codable {
    case woodClick
    case beep
    case woodblock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .woodClick: return "木质 click"
        case .beep: return "电子 beep"
        case .woodblock: return "低木鱼"
        }
    }

    /// 基准音高（重音在其上叠加半音）。
    var baseFrequency: Double {
        switch self {
        case .woodClick: return 1600
        case .beep: return 1200
        case .woodblock: return 800
        }
    }

    /// 噪声瞬态占比，决定「木头感」的强弱。
    var noiseMix: Double {
        switch self {
        case .woodClick: return 0.55
        case .beep: return 0.04
        case .woodblock: return 0.72
        }
    }

    /// 指数衰减系数，越大衰减越快。
    var decay: Double {
        switch self {
        case .woodClick: return 95
        case .beep: return 42
        case .woodblock: return 68
        }
    }

    /// 发声时长，必须短于最快速率下的拍间隔（240BPM = 250ms）。
    var duration: Double {
        switch self {
        case .woodClick: return 0.055
        case .beep: return 0.075
        case .woodblock: return 0.065
        }
    }
}
