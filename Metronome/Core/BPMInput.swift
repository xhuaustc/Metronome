import Foundation

/// BPM 输入的解析规则。抽成纯函数，是为了让「输入 999 → 400」「输入空 → 取消」
/// 这类边界行为可以被测试覆盖，而不依赖手点界面验证。
public enum BPMInput {

    public static let range = 20...400

    /// 返回 nil 表示「无效输入，保持原值」。合法值一律夹紧到 20–400。
    public static func parse(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed) else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    public static func clamp(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// 刻度随手指移动：向右拖动降低 BPM，向左拖动提高 BPM。
    public static func value(afterHorizontalDrag distance: Double, from base: Int) -> Int {
        guard distance.isFinite else { return clamp(base) }
        let magnitude = abs(distance)
        let scaled = magnitude <= 40 ? magnitude : 40 + (magnitude - 40) / 2
        let delta = min(scaled, Double(range.upperBound - range.lowerBound))
        let signedDelta = distance >= 0 ? -delta : delta
        return clamp(clamp(base) + Int(signedDelta.rounded()))
    }
}
