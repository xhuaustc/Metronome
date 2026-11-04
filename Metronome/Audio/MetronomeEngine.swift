import AVFoundation
import Foundation

/// 节拍器音频引擎。
///
/// 时钟契约（与 PRD 第 6 节一致）：
/// - 唯一时间源是 AVAudioPlayerNode 的采样帧。
/// - 每 100ms 唤醒一次，把未来 1.0s 的拍点按绝对采样帧排入播放器。
/// - 主线程卡顿不影响已排内容；界面只通过 `position()` 只读查询。
/// - 停止时 `player.stop()` 清空排队 buffer，立即静音且不残留。
final class MetronomeEngine {

    // MARK: - 状态（共享状态与 planner 由 lock 保护）

    private var storedBPM: Int = 96
    private var storedTimeSignature: TimeSignature = .fourFour
    private var storedSubdivision: Subdivision = .none
    private var storedAccentEnabled = true
    private var storedCountInEnabled = true
    private var storedTimbre: Timbre = .crystalTick
    private var storedVolume: Float = 0.85

    private(set) var bpm: Int {
        get { withStateLock { storedBPM } }
        set { withStateLock { storedBPM = newValue } }
    }
    private(set) var timeSignature: TimeSignature {
        get { withStateLock { storedTimeSignature } }
        set { withStateLock { storedTimeSignature = newValue } }
    }
    private(set) var subdivision: Subdivision {
        get { withStateLock { storedSubdivision } }
        set { withStateLock { storedSubdivision = newValue } }
    }
    private(set) var accentEnabled: Bool {
        get { withStateLock { storedAccentEnabled } }
        set { withStateLock { storedAccentEnabled = newValue } }
    }
    private(set) var countInEnabled: Bool {
        get { withStateLock { storedCountInEnabled } }
        set { withStateLock { storedCountInEnabled = newValue } }
    }
    private(set) var timbre: Timbre {
        get { withStateLock { storedTimbre } }
        set { withStateLock { storedTimbre = newValue } }
    }

    var volume: Float {
        get { withStateLock { storedVolume } }
        set {
            withStateLock { storedVolume = newValue }
            schedulerQueue.async { [weak self] in
                guard let self else { return }
                self.player.volume = self.volume
            }
        }
    }

    var isRunning: Bool { isPlaying }

    // MARK: - 节点

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let previewPlayer = AVAudioPlayerNode()
    private let sampleRate: Double
    private let format: AVAudioFormat
    private let bank: SoundBank
    private let planner: SchedulePlanner
    private let lock = NSLock()

    private func withStateLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: - 调度

    private let schedulerQueue = DispatchQueue(label: "com.metronome.scheduler", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var storedIsPlaying = false
    private var playbackGeneration: UInt64 = 0
    private var isPlaying: Bool {
        get { withStateLock { storedIsPlaying } }
        set {
            withStateLock {
                if storedIsPlaying != newValue { playbackGeneration &+= 1 }
                storedIsPlaying = newValue
            }
        }
    }
    private var didStartPlanner = false
    private var variantCursor = 0

    /// 前瞻窗口。10 倍于唤醒间隔，足以吸收任何主线程抖动。
    private let lookAheadSeconds = 1.0
    private let wakeInterval: TimeInterval = 0.1
    /// 从「按下按钮」到「第一声」的准备时间，用于给调度留出余量。
    private let startLatencySeconds = 0.025
    /// 迟到超过 1.5ms 的拍直接丢弃，绝不补响。
    private let overdueToleranceFrames: Double = 64

    // MARK: - 回调

    /// 系统中断（来电等）。引擎已自行停止并复位，界面只需更新状态。
    private var storedOnInterruptionBegan: (() -> Void)?
    var onInterruptionBegan: (() -> Void)? {
        get { withStateLock { storedOnInterruptionBegan } }
        set {
            let previous = withStateLock { () -> (() -> Void)? in
                let previous = storedOnInterruptionBegan
                storedOnInterruptionBegan = newValue
                return previous
            }
            withExtendedLifetime(previous) {}
        }
    }
    /// 音频服务重启或引擎意外停止，界面应复位显示。
    private var storedOnEngineFailed: (() -> Void)?
    var onEngineFailed: (() -> Void)? {
        get { withStateLock { storedOnEngineFailed } }
        set {
            let previous = withStateLock { () -> (() -> Void)? in
                let previous = storedOnEngineFailed
                storedOnEngineFailed = newValue
                return previous
            }
            withExtendedLifetime(previous) {}
        }
    }

    // MARK: - 初始化

    init(sampleRate: Double = 44100) {
        self.sampleRate = sampleRate
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        self.bank = SoundBank(sampleRate: sampleRate)
        self.planner = SchedulePlanner(sampleRate: sampleRate, bpm: 96, timeSignature: .fourFour)
        // reset 不会 detach 节点；只在初始化时 attach 一次。
        engine.attach(player)
        engine.attach(previewPlayer)
        buildGraph()
        observeAudioNotifications()
    }

    private func buildGraph() {
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.connect(previewPlayer, to: engine.mainMixerNode, format: format)
        engine.prepare()
        player.volume = volume
    }

    // MARK: - 传输控制

    func start() {
        schedulerQueue.async { [weak self] in
            guard let self, !self.isPlaying else { return }
            do {
                try self.activateSession()
                if !self.engine.isRunning {
                    try self.engine.start()
                }
                self.previewPlayer.stop()
                self.player.volume = self.volume
                self.player.play()

                self.variantCursor = 0
                self.didStartPlanner = false
                self.isPlaying = true
                self.startTimer()
            } catch {
                self.isPlaying = false
                DispatchQueue.main.async { self.onEngineFailed?() }
            }
        }
    }

    func stop() {
        schedulerQueue.async { [weak self] in
            self?.stopInternal()
        }
    }

    private func stopInternal() {
        previewPlayer.stop()
        guard isPlaying || timer != nil else {
            lock.lock(); planner.stop(); lock.unlock()
            return
        }
        isPlaying = false
        timer?.cancel()
        timer = nil
        didStartPlanner = false

        // stop 会丢弃所有已排 buffer，这是「立即静音、不残留尾音」的唯一可靠方式。
        player.stop()

        lock.lock()
        planner.stop()
        lock.unlock()
    }

    private func startTimer() {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: schedulerQueue)
        source.schedule(deadline: .now(), repeating: wakeInterval, leeway: .milliseconds(0))
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = source
        source.resume()
    }

    // MARK: - 调度

    private func tick() {
        guard isPlaying else { return }
        guard let now = currentPlayerFrame() else { return }

        if !didStartPlanner {
            withStateLock {
                planner.start(atFrame: now + startLatencySeconds * sampleRate,
                              countIn: storedCountInEnabled)
            }
            didStartPlanner = true
        }

        lock.lock()
        let points = planner.plan(upTo: now + lookAheadSeconds * sampleRate)
        lock.unlock()

        for point in points {
            // 迟到的点直接丢弃。宁可少一声，也不允许挤在一起补响。
            guard point.frame >= now - overdueToleranceFrames else { continue }
            schedule(point, at: max(point.frame, now + 1))
        }
    }

    private func schedule(_ point: SoundPoint, at frame: Double) {
        let variant = variantCursor % SoundBank.variantsPerLevel
        variantCursor &+= 1

        let buffer = bank.buffer(timbre: timbre,
                                 accent: point.accent,
                                 countIn: point.isCountIn,
                                 isSubdivision: !point.isMainBeat,
                                 variant: variant)
        // 按播放器采样帧调度；实际输出路径的延迟需要另行测量。
        let time = AVAudioTime(sampleTime: AVAudioFramePosition(frame.rounded()), atRate: sampleRate)
        player.scheduleBuffer(buffer, at: time, options: [], completionHandler: nil)
    }

    /// 当前播放头位置（采样帧），主线程与调度队列均可安全调用。
    private func currentPlayerFrame() -> Double? {
        guard let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return nil }
        return Double(playerTime.sampleTime)
    }

    /// 视觉层每帧调用。只读，不产生任何副作用。
    func position() -> PlaybackPosition? {
        // 不持锁查询 AVFoundation，并丢弃跨越停止或重启的旧播放头。
        guard let generation = withStateLock({ storedIsPlaying ? playbackGeneration : nil }),
              let frame = currentPlayerFrame() else { return nil }
        return withStateLock {
            guard storedIsPlaying, playbackGeneration == generation else { return nil }
            return planner.position(at: frame)
        }
    }

    /// 与 start/stop 在同一队列串行执行，快速停止再开始也使用最新方案。
    func configurePractice(_ configuration: TempoPracticeConfiguration?) {
        schedulerQueue.async { [weak self] in
            guard let self else { return }
            self.withStateLock { self.planner.configurePractice(configuration) }
        }
    }

    func requestPracticeAction(_ action: TempoPracticeAction) -> Int? {
        let frame = currentPlayerFrame()
        return withStateLock { planner.requestPracticeAction(action, atFrame: frame) }
    }

    /// 用户主动试听时才发声，独立节点不改变节拍播放头。
    func previewSound(_ timbre: Timbre) {
        schedulerQueue.async { [weak self] in
            guard let self, !self.isPlaying else { return }
            do {
                try self.activateSession()
                if !self.engine.isRunning { try self.engine.start() }
                self.previewPlayer.stop()
                self.previewPlayer.volume = self.volume
                self.previewPlayer.scheduleBuffer(self.bank.buffer(timbre: timbre, accent: .normal,
                                                                   countIn: false, isSubdivision: false, variant: 0))
                self.previewPlayer.play()
            } catch {
                DispatchQueue.main.async { self.onEngineFailed?() }
            }
        }
    }

    // MARK: - 参数

    func setBPM(_ value: Int) {
        withStateLock {
            storedBPM = value
            planner.setBPM(value)
        }
    }

    func setMeter(_ signature: TimeSignature, counting: BeatCounting, grouping: Int, bpm: Int) {
        withStateLock {
            storedTimeSignature = signature
            storedBPM = bpm
            planner.setMeter(signature, counting: counting, grouping: grouping, bpm: bpm)
        }
    }

    func setTimeSignature(_ value: TimeSignature) {
        withStateLock {
            storedTimeSignature = value
            planner.setTimeSignature(value)
        }
    }

    func setSubdivision(_ value: Subdivision) {
        withStateLock {
            storedSubdivision = value
            planner.setSubdivision(value)
        }
    }

    func setAccentEnabled(_ value: Bool) {
        withStateLock {
            storedAccentEnabled = value
            planner.setAccentEnabled(value)
        }
    }

    func setTimbre(_ value: Timbre) {
        timbre = value
    }

    func setCountIn(_ value: Bool) {
        countInEnabled = value
    }

    /// 播放中是否存在被延后到下一拍的变更。
    var hasPendingBeatChange: Bool {
        lock.lock(); defer { lock.unlock() }
        return planner.hasPendingTempoChange
    }

    /// 播放中是否存在被延后到下一小节的变更。
    var hasPendingBarChange: Bool {
        lock.lock(); defer { lock.unlock() }
        return planner.hasPendingBarChange
    }

    var currentSecondsPerBeat: Double {
        lock.lock(); defer { lock.unlock() }
        return planner.secondsPerBeat
    }

    // MARK: - 音频会话与系统事件

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPreferredSampleRate(sampleRate)
        try session.setActive(true, options: [])
    }

    private func observeAudioNotifications() {
        let center = NotificationCenter.default

        center.addObserver(forName: AVAudioSession.interruptionNotification,
                           object: nil,
                           queue: nil) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

            switch type {
            case .began:
                // 来电或其它 App 抢占：立即停止并复位到第一拍，且不自动恢复。
                self.schedulerQueue.async {
                    self.stopInternal()
                    DispatchQueue.main.async { self.onInterruptionBegan?() }
                }
            case .ended:
                // 只还原会话，绝不自动出声——解锁瞬间突然响是明确禁止的。
                self.schedulerQueue.async {
                    try? AVAudioSession.sharedInstance().setActive(true)
                }
            @unknown default:
                break
            }
        }

        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                           object: nil,
                           queue: nil) { [weak self] _ in
            guard let self else { return }
            self.schedulerQueue.async {
                self.stopInternal()
                self.engine.stop()
                self.engine.reset()
                self.buildGraph()
                DispatchQueue.main.async { self.onEngineFailed?() }
            }
        }

        center.addObserver(forName: AVAudioSession.routeChangeNotification,
                           object: nil,
                           queue: nil) { [weak self] _ in
            guard let self else { return }
            self.schedulerQueue.async {
                // 路由切换通常由系统无缝接管；只有引擎真的停了才需要复位。
                if self.isPlaying && !self.engine.isRunning {
                    self.stopInternal()
                    DispatchQueue.main.async { self.onEngineFailed?() }
                }
            }
        }
    }

    deinit {
        timer?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}
