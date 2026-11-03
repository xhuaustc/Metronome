import Foundation

/// BPM 输入的解析规则。抽成纯函数，是为了让「输入 999 → 240」「输入空 → 取消」
/// 这类边界行为可以被测试覆盖，而不依赖手点界面验证。
public enum BPMInput {

    public static let range = 30...240

    /// 返回 nil 表示「无效输入，保持原值」。合法值一律夹紧到 30–240。
    public static func parse(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed) else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    public static func clamp(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
