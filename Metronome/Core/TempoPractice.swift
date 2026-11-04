import Foundation

/// 只持久化练习方案；每次开始均重新计数，不保存上次运行进度。
public struct TempoPracticeConfiguration: Codable, Equatable, Sendable {
    public var enabled = false
    public var startBPM = 60
    public var targetBPM = 96
    public var increment = 4
    public var barsPerStep = 8

    public var isValid: Bool {
        BPMInput.range.contains(startBPM) && BPMInput.range.contains(targetBPM)
            && targetBPM >= startBPM && (1...40).contains(increment) && (1...32).contains(barsPerStep)
    }

    public func sanitized() -> Self {
        var result = self
        result.startBPM = BPMInput.clamp(startBPM)
        result.targetBPM = max(result.startBPM, BPMInput.clamp(targetBPM))
        result.increment = min(max(increment, 1), 40)
        result.barsPerStep = min(max(barsPerStep, 1), 32)
        return result
    }
}

public enum TempoPracticeAction: Equatable, Sendable {
    case hold, resume, stepBack
}

/// 来自实际播放位置的只读快照，不使用 UI 计时器决定何时提速。
public struct TempoPracticeProgress: Equatable, Sendable {
    public let bpm: Int
    public let targetBPM: Int
    public let stageBar: Int
    public let barsPerStep: Int
    public let isHolding: Bool
    /// 已实际播放的操作编号，用于确认前瞻调度中的手动控制已生效。
    public var actionRevision: Int = 0
    public var reachedTarget: Bool { bpm >= targetBPM }
}
