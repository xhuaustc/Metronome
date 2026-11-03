import Foundation

/// 每拍内的细分档位。partsPerBeat 即每拍发声次数（含主拍本身）。
public enum Subdivision: Int, Codable, CaseIterable, Sendable, Identifiable {
    case none = 1
    case two = 2
    case three = 3
    case four = 4

    public var id: Int { rawValue }

    public var partsPerBeat: Int { rawValue }

    public var label: String {
        switch self {
        case .none: return "无"
        case .two: return "二等"
        case .three: return "三等"
        case .four: return "四等"
        }
    }

    /// 细分音相对主拍的增益（线性），约 -14 dB。
    public var gain: Float { self == .none ? 0 : 0.2 }
}

/// 一个声点，即一次实际发声。frame 为绝对采样帧，是全应用唯一的计时单位。
public struct SoundPoint: Equatable, Sendable {
    public let frame: Double
    /// 小节内主拍序号，0-based。
    public let beat: Int
    /// 0 表示主拍本身，>0 表示该拍内的第几个细分。
    public let part: Int
    public let accent: AccentLevel
    public let isCountIn: Bool
    /// 正式小节从 1 开始；预备拍期间为 0。
    public let barNumber: Int

    public var isMainBeat: Bool { part == 0 }

    public init(frame: Double,
                beat: Int,
                part: Int,
                accent: AccentLevel,
                isCountIn: Bool,
                barNumber: Int) {
        self.frame = frame
        self.beat = beat
        self.part = part
        self.accent = accent
        self.isCountIn = isCountIn
        self.barNumber = barNumber
    }
}

/// 视觉层读取的播放位置快照。
public struct PlaybackPosition: Equatable, Sendable {
    public let beat: Int
    public let part: Int
    public let barNumber: Int
    public let isCountIn: Bool
    public let accent: AccentLevel
    /// 当前声点到下一次发声之间的进度 0...1，用于按钮外圈弧。
    public let progress: Double
    /// 距离下一次发声还有多少秒（视觉提前量可用），无下一声时为 nil。
    public let secondsToNext: Double?
}
