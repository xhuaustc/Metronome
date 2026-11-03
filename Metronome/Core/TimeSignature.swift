import Foundation

/// 拍单位：BPM 所指的音符时值，由拍号分母决定。
public enum BeatUnit: String, Codable, Sendable {
    case quarter
    case eighth

    public var symbol: String {
        switch self {
        case .quarter: return "♩"
        case .eighth: return "♪"
        }
    }
}

/// 重音层级。三级而非两级，是为了让 6/8 的 3+3 分组在听感上成立。
public enum AccentLevel: Int, Codable, Sendable, Comparable {
    case normal = 0
    case group = 1
    case strong = 2

    public static func < (lhs: AccentLevel, rhs: AccentLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 相对基准音高的半音偏移。
    public var semitoneOffset: Int {
        switch self {
        case .normal: return 0
        case .group: return 4
        case .strong: return 7
        }
    }
}

/// V1 支持的拍号。BPM 恒等于「拍单位」的每分钟个数：
/// 分母为 4 时 BPM 指四分音符，分母为 8 时指八分音符。
public enum TimeSignature: String, CaseIterable, Codable, Sendable, Identifiable {
    case twoFour = "2/4"
    case threeFour = "3/4"
    case fourFour = "4/4"
    case threeEight = "3/8"
    case sixEight = "6/8"

    public var id: String { rawValue }
    public var display: String { rawValue }

    public var numerator: Int {
        switch self {
        case .twoFour: return 2
        case .threeFour, .threeEight: return 3
        case .fourFour: return 4
        case .sixEight: return 6
        }
    }

    public var denominator: Int {
        switch self {
        case .twoFour, .threeFour, .fourFour: return 4
        case .threeEight, .sixEight: return 8
        }
    }

    public var beatUnit: BeatUnit {
        denominator == 8 ? .eighth : .quarter
    }

    /// 每小节主拍数，等于分子。
    public var beatsPerBar: Int { numerator }

    /// 主拍的分组结构，决定次级重音位置。6/8 为 3+3。
    public var groups: [Int] {
        switch self {
        case .sixEight: return [3, 3]
        default: return [numerator]
        }
    }

    public var isCompound: Bool { groups.count > 1 }

    /// 小节内第 index 个主拍（0-based）的重音层级。
    public func accent(atBeat index: Int) -> AccentLevel {
        guard index > 0 else { return .strong }
        guard isCompound else { return .normal }
        var cursor = 0
        for size in groups {
            if cursor == index { return .group }
            cursor += size
        }
        return .normal
    }

    /// 谱面上以附点四分音符记速时，等价值 = bpm / dotFactor。
    /// 仅当一小节可被 3 个八分音符整除时有意义（3/8、6/8）。
    public var dottedQuarterFactor: Double? {
        guard denominator == 8, numerator % 3 == 0 else { return nil }
        return 3.0
    }

    /// 用于界面标注：`♩ = 96` / `♪ = 96`
    public func tempoLabel(bpm: Int) -> String {
        "\(beatUnit.symbol) = \(bpm)"
    }

    /// 换算提示，如 6/8 下 `♩. = 32`；无意义时返回 nil。
    public func dottedEquivalentLabel(bpm: Int) -> String? {
        guard let factor = dottedQuarterFactor else { return nil }
        let value = Double(bpm) / factor
        return "♩. = \(Int(value.rounded()))"
    }
}
