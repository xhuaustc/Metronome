import Foundation

/// 节拍调度器：把「速度 + 拍号 + 细分」翻译成一串绝对采样帧。
///
/// 三条不可破坏的规则：
/// 1. 所有时间都由 `anchorFrame + n * framesPerBeat` 一次乘法得出，不做累加，
///    因此不存在浮点累积漂移。
/// 2. 参数变更只影响尚未生成的拍，已生成的拍不重算，因此不会补响或叠音。
/// 3. 游标单调前进，同一帧不会被生成两次。
public final class SchedulePlanner {

    public let sampleRate: Double

    public private(set) var bpm: Int
    public private(set) var timeSignature: TimeSignature
    public private(set) var subdivision: Subdivision
    public private(set) var accentEnabled: Bool

    private var pendingBPM: Int?
    private var pendingSignature: TimeSignature?
    private var pendingSubdivision: Subdivision?
    private var pendingAccent: Bool?

    private var running = false
    private var countingIn = false

    private var beatIndex = 0
    private var partIndex = 0
    private var barNumber = 1

    private var framesPerBeat: Double = 0
    private var anchorFrame: Double = 0
    private var anchorBeat: Int = 0
    private var beatFrame: Double = 0
    private var startedFrame: Double = 0

    private var history: [SoundPoint] = []

    public init(sampleRate: Double,
                bpm: Int,
                timeSignature: TimeSignature,
                subdivision: Subdivision = .none,
                accentEnabled: Bool = true) {
        self.sampleRate = sampleRate
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.subdivision = subdivision
        self.accentEnabled = accentEnabled
        self.framesPerBeat = sampleRate * 60.0 / Double(bpm)
    }

    public var isRunning: Bool { running }
    public var isCountingIn: Bool { countingIn }
    public var secondsPerBeat: Double { 60.0 / Double(bpm) }

    // MARK: - 生命周期

    /// 从第一拍开始。frame 必须是音频引擎当前的渲染帧。
    public func start(atFrame frame: Double, countIn: Bool) {
        running = true
        countingIn = countIn
        beatIndex = 0
        partIndex = 0
        barNumber = countIn ? 0 : 1
        startedFrame = frame
        anchorFrame = frame
        anchorBeat = 0
        beatFrame = frame
        framesPerBeat = sampleRate * 60.0 / Double(bpm)
        history.removeAll(keepingCapacity: true)
    }

    /// 停止并复位到第一拍。待生效的参数会立即落地，避免下次开始时残留旧值。
    public func stop() {
        running = false
        countingIn = false
        beatIndex = 0
        partIndex = 0
        barNumber = 1
        history.removeAll(keepingCapacity: true)
        commitPending()
    }

    // MARK: - 参数变更

    /// 下一拍生效。
    public func setBPM(_ value: Int) {
        let clamped = min(max(value, 30), 240)
        guard clamped != bpm else {
            pendingBPM = nil
            return
        }
        if running {
            pendingBPM = clamped
        } else {
            bpm = clamped
            framesPerBeat = sampleRate * 60.0 / Double(bpm)
        }
    }

    /// 下一小节首拍生效。
    public func setTimeSignature(_ value: TimeSignature) {
        guard value != timeSignature else {
            pendingSignature = nil
            return
        }
        if running { pendingSignature = value } else { timeSignature = value }
    }

    /// 下一小节首拍生效。
    public func setSubdivision(_ value: Subdivision) {
        guard value != subdivision else {
            pendingSubdivision = nil
            return
        }
        if running { pendingSubdivision = value } else { subdivision = value }
    }

    /// 下一小节首拍生效。
    public func setAccentEnabled(_ value: Bool) {
        guard value != accentEnabled else {
            pendingAccent = nil
            return
        }
        if running { pendingAccent = value } else { accentEnabled = value }
    }

    /// 把待生效的参数立即落地（停止时调用）。
    public func commitPending() {
        if let value = pendingBPM {
            bpm = value
            framesPerBeat = sampleRate * 60.0 / Double(bpm)
            pendingBPM = nil
        }
        if let value = pendingSignature { timeSignature = value; pendingSignature = nil }
        if let value = pendingSubdivision { subdivision = value; pendingSubdivision = nil }
        if let value = pendingAccent { accentEnabled = value; pendingAccent = nil }
    }

    /// 是否存在被延后到下一拍的变更，供界面提示使用。
    public var hasPendingTempoChange: Bool { pendingBPM != nil }

    /// 是否存在被延后到下一小节的变更。
    public var hasPendingBarChange: Bool {
        pendingSignature != nil || pendingSubdivision != nil || pendingAccent != nil
    }

    // MARK: - 生成

    /// 生成所有 `frame < limit` 且尚未生成的声点，按时间升序。
    public func plan(upTo limit: Double, maxPoints: Int = 512) -> [SoundPoint] {
        guard running else { return [] }
        var output: [SoundPoint] = []
        output.reserveCapacity(16)

        while output.count < maxPoints, beatFrame < limit {
            let parts = subdivision.partsPerBeat
            let offset = parts > 1 ? Double(partIndex) * framesPerBeat / Double(parts) : 0
            let point = SoundPoint(frame: beatFrame + offset,
                                   beat: beatIndex,
                                   part: partIndex,
                                   accent: accentEnabled ? timeSignature.accent(atBeat: beatIndex) : .normal,
                                   isCountIn: countingIn,
                                   barNumber: barNumber)
            output.append(point)
            record(point)
            advance()
        }
        return output
    }

    private func advance() {
        partIndex += 1
        if partIndex < subdivision.partsPerBeat { return }

        partIndex = 0

        // 此刻 beatFrame 仍是刚发出的那一拍。速度变更必须以「这一拍」为新段锚点，
        // 而不是以按旧速度推算出的下一拍位置为锚点，否则新间隔会被吞掉。
        if let value = pendingBPM {
            pendingBPM = nil
            bpm = value
            framesPerBeat = sampleRate * 60.0 / Double(bpm)
            anchorFrame = beatFrame
            anchorBeat = beatIndex
        }

        beatIndex += 1
        beatFrame = anchorFrame + Double(beatIndex - anchorBeat) * framesPerBeat

        if beatIndex >= timeSignature.beatsPerBar {
            endOfBar()
        }
    }

    private func endOfBar() {
        if countingIn {
            countingIn = false
            barNumber = 1
        } else {
            barNumber += 1
        }

        if let value = pendingSignature { timeSignature = value; pendingSignature = nil }
        if let value = pendingSubdivision { subdivision = value; pendingSubdivision = nil }
        if let value = pendingAccent { accentEnabled = value; pendingAccent = nil }

        beatIndex = 0
        partIndex = 0
        anchorFrame = beatFrame
        anchorBeat = 0
        framesPerBeat = sampleRate * 60.0 / Double(bpm)
    }

    // MARK: - 视觉查询

    private func record(_ point: SoundPoint) {
        history.append(point)
        if history.count > 256 {
            history.removeFirst(history.count - 128)
        }
    }

    /// 供视觉层每帧调用：只读，不改变任何状态。
    public func position(at frame: Double) -> PlaybackPosition? {
        guard running, !history.isEmpty, frame >= startedFrame else { return nil }
        guard let index = lastIndex(atOrBefore: frame) else { return nil }

        let current = history[index]
        let next: SoundPoint? = index + 1 < history.count ? history[index + 1] : nil
        let nextFrame = next?.frame ?? (current.frame + framesPerBeat / Double(subdivision.partsPerBeat))
        let span = nextFrame - current.frame
        let progress = span > 0 ? min(max((frame - current.frame) / span, 0), 1) : 0

        return PlaybackPosition(beat: current.beat,
                                part: current.part,
                                barNumber: current.barNumber,
                                isCountIn: current.isCountIn,
                                accent: current.accent,
                                progress: progress,
                                secondsToNext: next == nil ? nil : (nextFrame - frame) / sampleRate)
    }

    private func lastIndex(atOrBefore frame: Double) -> Int? {
        var low = 0
        var high = history.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if history[mid].frame <= frame {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}
