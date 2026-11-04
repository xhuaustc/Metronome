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

    private var practice: TempoPracticeConfiguration?
    private var completedPracticeBars = 0
    private var practiceHolding = false
    private var pendingPracticeAction: (action: TempoPracticeAction, bpm: Int, revision: Int)?
    private var requestedPracticeRevision = 0
    private var appliedPracticeRevision = 0

    private var pendingBPM: Int?
    public private(set) var beatCounting: BeatCounting = .written
    public private(set) var grouping = 0
    private var pendingMeter: (signature: TimeSignature, counting: BeatCounting, grouping: Int, bpm: Int?)?
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

    private struct VisualPoint {
        let point: SoundPoint
        let beatOrdinal: Int
        let partsPerBeat: Int
        let framesPerBeat: Double
        let timeSignature: TimeSignature
        let beatsPerBar: Int
        let bpm: Int
        let practice: TempoPracticeProgress?
    }
    private var beatOrdinal = 0
    private var history: [VisualPoint] = []

    public init(sampleRate: Double,
                bpm: Int,
                timeSignature: TimeSignature,
                subdivision: Subdivision = .none,
                accentEnabled: Bool = true,
                beatCounting: BeatCounting = .written,
                grouping: Int = 0) {
        self.sampleRate = sampleRate
        self.bpm = BPMInput.clamp(bpm)
        self.timeSignature = timeSignature
        self.beatCounting = timeSignature.isCompound ? beatCounting : .written
        self.grouping = min(max(grouping, 0), timeSignature.groupingOptions.count - 1)
        self.subdivision = subdivision
        self.accentEnabled = accentEnabled
        self.framesPerBeat = sampleRate * 60.0 / Double(self.bpm)
    }

    public var isRunning: Bool { running }
    public var isCountingIn: Bool { countingIn }
    public var secondsPerBeat: Double { 60.0 / Double(bpm) }

    // MARK: - 生命周期

    /// 从第一拍开始。frame 必须是音频引擎当前的渲染帧。
    public func start(atFrame frame: Double, countIn: Bool) {
        if let practice { bpm = practice.startBPM }
        completedPracticeBars = 0
        practiceHolding = false
        pendingPracticeAction = nil
        requestedPracticeRevision = 0
        appliedPracticeRevision = 0
        running = true
        countingIn = countIn
        beatIndex = 0
        beatOrdinal = 0
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
        beatOrdinal = 0
        partIndex = 0
        barNumber = 1
        history.removeAll(keepingCapacity: true)
        commitPending()
        pendingPracticeAction = nil
        completedPracticeBars = 0
        practiceHolding = false
    }

    public func configurePractice(_ configuration: TempoPracticeConfiguration?) {
        guard !running else { return }
        practice = configuration.flatMap { $0.enabled ? $0.sanitized() : nil }
    }

    @discardableResult
    public func requestPracticeAction(_ action: TempoPracticeAction, atFrame frame: Double? = nil) -> Int? {
        guard running, practice != nil else { return nil }
        // 操作基于用户实际听到的档位，不能使用前瞻调度已推进到的未来档位。
        let audibleBPM = frame.flatMap { position(at: $0)?.bpm } ?? bpm
        requestedPracticeRevision += 1
        pendingPracticeAction = (action, audibleBPM, requestedPracticeRevision)
        return requestedPracticeRevision
    }

    private var practiceProgress: TempoPracticeProgress? {
        guard let practice else { return nil }
        return TempoPracticeProgress(bpm: bpm, targetBPM: practice.targetBPM,
                                     stageBar: completedPracticeBars + 1, barsPerStep: practice.barsPerStep,
                                     isHolding: practiceHolding, actionRevision: appliedPracticeRevision)
    }

    private func advancePractice(completedBar: Bool) {
        guard let practice else { return }
        if let request = pendingPracticeAction {
            pendingPracticeAction = nil
            appliedPracticeRevision = request.revision
            switch request.action {
            case .hold:
                bpm = request.bpm
                practiceHolding = true
            case .resume:
                bpm = request.bpm
                practiceHolding = false
                completedPracticeBars = 0
            case .stepBack:
                bpm = practice.startBPM + max(0, request.bpm - practice.startBPM - 1) / practice.increment * practice.increment
                practiceHolding = true
                completedPracticeBars = 0
            }
            return
        }
        guard completedBar, !practiceHolding, bpm < practice.targetBPM else { return }
        completedPracticeBars += 1
        if completedPracticeBars >= practice.barsPerStep {
            bpm = min(bpm + practice.increment, practice.targetBPM)
            completedPracticeBars = 0
        }
    }

    // MARK: - 参数变更

    /// 下一拍生效。
    public func setBPM(_ value: Int) {
        let clamped = BPMInput.clamp(value)
        if pendingMeter?.bpm != nil {
            pendingMeter?.bpm = clamped
            return
        }
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

    /// 拍号、计拍单位、分组和单位换算后的 BPM 在同一小节边界生效。
    public func setMeter(_ signature: TimeSignature, counting: BeatCounting, grouping: Int, bpm targetBPM: Int? = nil) {
        let counting: BeatCounting = signature.isCompound ? counting : .written
        let grouping = min(max(grouping, 0), signature.groupingOptions.count - 1)
        if running {
            pendingMeter = (signature, counting, grouping, targetBPM.map(BPMInput.clamp))
            if targetBPM != nil { pendingBPM = nil }
        } else {
            timeSignature = signature
            beatCounting = counting
            self.grouping = grouping
            if let targetBPM { bpm = BPMInput.clamp(targetBPM) }
            framesPerBeat = sampleRate * 60 / Double(bpm)
        }
    }

    public func setTimeSignature(_ value: TimeSignature) {
        guard value != timeSignature else { pendingMeter = nil; return }
        setMeter(value, counting: beatCounting, grouping: grouping)
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
        commitMeter()
        if let value = pendingSubdivision { subdivision = value; pendingSubdivision = nil }
        if let value = pendingAccent { accentEnabled = value; pendingAccent = nil }
    }

    /// 是否存在被延后到下一拍的变更，供界面提示使用。
    public var hasPendingTempoChange: Bool { pendingBPM != nil }

    /// 是否存在被延后到下一小节的变更。
    public var hasPendingBarChange: Bool {
        pendingMeter != nil || pendingSubdivision != nil || pendingAccent != nil
    }

    // MARK: - 生成

    /// 生成所有 `frame < limit` 且尚未生成的声点，按时间升序。
    public func plan(upTo limit: Double, maxPoints: Int = 512) -> [SoundPoint] {
        guard running else { return [] }
        var output: [SoundPoint] = []
        output.reserveCapacity(16)

        while output.count < maxPoints {
            let parts = subdivision.partsPerBeat
            let offset = parts > 1 ? Double(partIndex) * framesPerBeat / Double(parts) : 0
            let pointFrame = beatFrame + offset
            guard pointFrame < limit else { break }
            if partIndex == 0, let value = pendingBPM {
                pendingBPM = nil
                bpm = value
                framesPerBeat = sampleRate * 60.0 / Double(bpm)
                anchorFrame = beatFrame
                anchorBeat = beatIndex
            }
            let point = SoundPoint(frame: pointFrame,
                                   beat: beatIndex,
                                   part: partIndex,
                                   accent: accentEnabled ? timeSignature.accent(atBeat: beatIndex, counting: beatCounting, grouping: grouping) : .normal,
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

        // 当前拍按原速度完成，下一拍的位置由原速度确定。
        beatIndex += 1
        beatOrdinal += 1
        beatFrame = anchorFrame + Double(beatIndex - anchorBeat) * framesPerBeat

        if beatIndex >= timeSignature.beatCount(beatCounting) {
            endOfBar()
        }
    }

    private func endOfBar() {
        let completedPracticeBar = !countingIn
        if countingIn {
            countingIn = false
            barNumber = 1
        } else {
            barNumber += 1
        }

        commitMeter()
        if let value = pendingSubdivision { subdivision = value; pendingSubdivision = nil }
        if let value = pendingAccent { accentEnabled = value; pendingAccent = nil }

        advancePractice(completedBar: completedPracticeBar)

        beatIndex = 0
        partIndex = 0
        anchorFrame = beatFrame
        anchorBeat = 0
        framesPerBeat = sampleRate * 60.0 / Double(bpm)
    }

    private func commitMeter() {
        guard let meter = pendingMeter else { return }
        timeSignature = meter.signature
        beatCounting = meter.counting
        grouping = meter.grouping
        if let value = meter.bpm { bpm = value }
        pendingMeter = nil
        framesPerBeat = sampleRate * 60 / Double(bpm)
    }

    // MARK: - 视觉查询

    private func record(_ point: SoundPoint) {
        history.append(VisualPoint(point: point, beatOrdinal: beatOrdinal,
                                   partsPerBeat: subdivision.partsPerBeat, framesPerBeat: framesPerBeat,
                                   timeSignature: timeSignature, beatsPerBar: timeSignature.beatCount(beatCounting),
                                   bpm: bpm, practice: practiceProgress))
        if history.count > 256 {
            history.removeFirst(history.count - 128)
        }
    }

    /// 供视觉层每帧调用：只读，不改变任何状态。
    public func position(at frame: Double) -> PlaybackPosition? {
        guard running, !history.isEmpty, frame >= startedFrame else { return nil }
        guard let index = lastIndex(atOrBefore: frame) else { return nil }

        let visual = history[index]
        let current = visual.point
        let next: SoundPoint? = index + 1 < history.count ? history[index + 1].point : nil
        let nextFrame = next?.frame ?? (current.frame + visual.framesPerBeat / Double(visual.partsPerBeat))
        let span = nextFrame - current.frame
        let progress = span > 0 ? min(max((frame - current.frame) / span, 0), 1) : 0

        return PlaybackPosition(bpm: visual.bpm, practice: visual.practice,
                                timeSignature: visual.timeSignature,
                                beatsPerBar: visual.beatsPerBar,
                                partsPerBeat: visual.partsPerBeat,
                                beat: current.beat,
                                part: current.part,
                                barNumber: current.barNumber,
                                isCountIn: current.isCountIn,
                                accent: current.accent,
                                progress: progress,
                                secondsToNext: next == nil ? nil : (nextFrame - frame) / sampleRate,
                                pendulumPhase: Double(visual.beatOrdinal % 2) + (Double(current.part) + progress) / Double(visual.partsPerBeat))
    }

    private func lastIndex(atOrBefore frame: Double) -> Int? {
        var low = 0
        var high = history.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if history[mid].point.frame <= frame {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}
