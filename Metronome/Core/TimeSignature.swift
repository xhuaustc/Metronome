import Foundation

/// 拍单位：BPM 所指的音符时值，由拍号分母决定。
public enum BeatUnit: String, Codable, Sendable {
    case half
    case quarter
    case eighth
    case dottedQuarter
    case dottedHalf

    public var symbol: String {
        switch self {
        case .half: return "𝅗𝅥"
        case .dottedQuarter: return "♩."
        case .dottedHalf: return "𝅗𝅥."
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

/// 计拍方式：旧数据默认按谱面分母计拍，复拍子可按附点音符大拍计拍。
public enum BeatCounting: String, Codable, CaseIterable, Sendable {
    case written, grouped
    public var title: String { self == .grouped ? "按大拍" : "按小拍" }
}

public enum TimeSignature: String, CaseIterable, Codable, Sendable, Identifiable {
    case twoFour = "2/4", threeFour = "3/4", fourFour = "4/4"
    case threeEight = "3/8", sixEight = "6/8", nineEight = "9/8", twelveEight = "12/8"
    case twoTwo = "2/2", threeTwo = "3/2", sixFour = "6/4"
    case fiveFour = "5/4", sevenFour = "7/4", fiveEight = "5/8", sevenEight = "7/8"

    public var id: String { rawValue }
    public var display: String { rawValue }
    public static let common: [Self] = [.twoFour, .threeFour, .fourFour, .sixEight]
    public var numerator: Int { Int(rawValue.split(separator: "/")[0])! }
    public var denominator: Int { Int(rawValue.split(separator: "/")[1])! }
    public var beatUnit: BeatUnit { denominator == 2 ? .half : denominator == 8 ? .eighth : .quarter }
    public var beatsPerBar: Int { numerator }
    public var isCompound: Bool { [.sixEight, .nineEight, .twelveEight, .sixFour].contains(self) }
    public var isIrregular: Bool { numerator == 5 || numerator == 7 }

    public var groupingOptions: [[Int]] {
        if numerator == 5 { return [[2, 3], [3, 2]] }
        if numerator == 7 { return [[2, 2, 3], [3, 2, 2], [2, 3, 2]] }
        if isCompound { return [Array(repeating: 3, count: numerator / 3)] }
        return [[numerator]]
    }
    public var groups: [Int] { groupingOptions[0] }
    public func groups(grouping: Int) -> [Int] { groupingOptions[min(max(grouping, 0), groupingOptions.count - 1)] }
    public func beatCount(_ counting: BeatCounting) -> Int { isCompound && counting == .grouped ? numerator / 3 : numerator }
    public func unit(_ counting: BeatCounting) -> BeatUnit {
        guard isCompound && counting == .grouped else { return beatUnit }
        return denominator == 8 ? .dottedQuarter : .dottedHalf
    }
    public func unitsPerBeat(_ counting: BeatCounting) -> Int { isCompound && counting == .grouped ? 3 : 1 }
    public func accent(atBeat index: Int, counting: BeatCounting = .written, grouping: Int = 0) -> AccentLevel {
        guard index > 0 else { return .strong }
        if isCompound && counting == .grouped {
            // 四大拍的复拍子在第三大拍保留次重音。
            return numerator == 12 && index == 2 ? .group : .normal
        }
        guard isCompound || isIrregular else { return .normal }
        var cursor = 0
        for size in groups(grouping: grouping) {
            if cursor == index { return .group }
            cursor += size
        }
        return .normal
    }
    public var dottedQuarterFactor: Double? { denominator == 8 && numerator % 3 == 0 ? 3 : nil }
    public func tempoLabel(bpm: Int, counting: BeatCounting = .written) -> String { "\(unit(counting).symbol) = \(bpm)" }
    public func dottedEquivalentLabel(bpm: Int) -> String? {
        guard let factor = dottedQuarterFactor else { return nil }
        return "♩. = \(Int((Double(bpm) / factor).rounded()))"
    }
}
