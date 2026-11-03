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

    // MARK: - 状态（由 UI 写入，调度队列读取）

    private(set) var bpm: Int = 96
    private(set) var timeSignature: TimeSignature = .fourFour
    private(set) var subdivision: Subdivision = .none
    private(set) var accentEnabled: Bool = true
    private(set) var countInEnabled: Bool = true
    private(set) var timbre: Timbre = .woodClick

    var volume: Float = 0.85 {
        didSet { player.volume = volume }
    }

    var isRunning: Bool { isPlaying }

    // MARK: - 节点

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double
    private let format: AVAudioFormat
    private let bank: SoundBank
    private let planner: SchedulePlanner
    private let lock = NSLock()

    // MARK: - 调度

    private let schedulerQueue = DispatchQueue(label: "com.metronome.scheduler", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var isPlaying = false
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
    var onInterruptionBegan: (() -> Void)?
    /// 音频服务重启或引擎意外停止，界面应复位显示。
    var onEngineFailed: (() -> Void)?

    // MARK: - 初始化

    init(sampleRate: Double = 44100) {
        self.sampleRate = sampleRate
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        self.bank = SoundBank(sampleRate: sampleRate)
        self.planner = SchedulePlanner(sampleRate: sampleRate, bpm: 96, timeSignature: .fourFour)
        buildGraph()
        observeAudioNotifications()
    }

    private func buildGraph() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
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
            lock.lock()
            planner.start(atFrame: now + startLatencySeconds * sampleRate,
                          countIn: countInEnabled)
            lock.unlock()
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
        // 输出延迟补偿：让「听到的时刻」而非「送入硬件的时刻」对齐节拍。
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
        guard isPlaying, let frame = currentPlayerFrame() else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return planner.position(at: frame)
    }

    // MARK: - 参数

    func setBPM(_ value: Int) {
        bpm = value
        lock.lock(); planner.setBPM(value); lock.unlock()
    }

    func setTimeSignature(_ value: TimeSignature) {
        timeSignature = value
        lock.lock(); planner.setTimeSignature(value); lock.unlock()
    }

    func setSubdivision(_ value: Subdivision) {
        subdivision = value
        lock.lock(); planner.setSubdivision(value); lock.unlock()
    }

    func setAccentEnabled(_ value: Bool) {
        accentEnabled = value
        lock.lock(); planner.setAccentEnabled(value); lock.unlock()
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
                self.stop()
                DispatchQueue.main.async { self.onInterruptionBegan?() }
            case .ended:
                // 只还原会话，绝不自动出声——解锁瞬间突然响是明确禁止的。
                try? AVAudioSession.sharedInstance().setActive(true)
            @unknown default:
                break
            }
        }

        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                           object: nil,
                           queue: nil) { [weak self] _ in
            guard let self else { return }
            self.schedulerQueue.async {
                self.isPlaying = false
                self.timer?.cancel()
                self.timer = nil
                self.player.stop()
                self.engine.stop()
                self.engine.reset()
                self.buildGraph()
                self.lock.lock()
                self.planner.stop()
                self.lock.unlock()
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
