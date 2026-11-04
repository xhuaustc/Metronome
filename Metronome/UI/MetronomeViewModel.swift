import SwiftUI
import UIKit

@MainActor
final class MetronomeViewModel: ObservableObject {

    @Published private(set) var settings: MetronomeSettings
    @Published private(set) var favorites = RhythmFavorites.load()
    @Published private(set) var isRunning = false
    @Published var banner: String?
    @Published private(set) var playbackPosition: PlaybackPosition?
    @Published private(set) var pendingPracticeAction: TempoPracticeAction?
    private var pendingPracticeRevision: Int?

    /// 非 nil 表示 BPM 正处于输入态。放在 ViewModel 而不是视图局部，
    /// 是为了让键盘工具栏、空白点击、失焦三条路径都能拿到同一份草稿。
    @Published var bpmDraft: String?

    let engine: MetronomeEngine

    private var saveTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var playbackObservationTask: Task<Void, Never>?

    init(engine: MetronomeEngine = MetronomeEngine()) {
        self.engine = engine
        self.settings = SettingsStore.load()
        applyAllToEngine()

        engine.onInterruptionBegan = { [weak self] in
            guard let self else { return }
            self.finishPlaybackUI()
            self.show(banner: "已被系统音频中断，已复位到第一拍")
        }

        engine.onEngineFailed = { [weak self] in
            guard let self else { return }
            self.finishPlaybackUI()
            self.show(banner: "音频引擎已重置，请重新开始")
        }
    }

    // MARK: - 只读访问

    var bpm: Int {
        guard settings.practice.enabled else { return settings.bpm }
        return isRunning ? playbackPosition?.bpm ?? settings.practice.startBPM : settings.practice.startBPM
    }
    var isPracticeRunning: Bool { isRunning && settings.practice.enabled }
    var practiceProgress: TempoPracticeProgress? { playbackPosition?.practice }
    var sound: Timbre { settings.timbre }
    var practiceStatus: String {
        guard isRunning else { return "每 \(settings.practice.barsPerStep) 小节 +\(settings.practice.increment) BPM" }
        if let action = pendingPracticeAction {
            switch action {
            case .hold: return "已收到保持 · 后续小节生效"
            case .resume: return "已收到继续 · 后续小节生效"
            case .stepBack: return "已收到退档 · 后续小节生效"
            }
        }
        if playbackPosition?.isCountIn == true { return "预备拍" }
        guard let progress = practiceProgress else { return "准备中" }
        if progress.isHolding { return "保持 \(progress.bpm) BPM" }
        if progress.reachedTarget { return "已到目标 · 保持播放" }
        return "第 \(progress.stageBar)/\(progress.barsPerStep) 小节 · 目标 \(progress.targetBPM)"
    }
    var timeSignature: TimeSignature { settings.timeSignature }
    var subdivision: Subdivision { settings.subdivision }
    var appearance: MetronomeAppearance { settings.theme }
    var accentEnabled: Bool { settings.accentEnabled }
    var countInEnabled: Bool { settings.countInEnabled }
    var keepAwake: Bool { settings.keepAwake }
    var volume: Double { settings.volume }

    var beatCounting: BeatCounting { settings.beatCounting }
    var grouping: Int { settings.grouping }
    var beatsPerBar: Int { timeSignature.beatCount(beatCounting) }
    var tempoLabel: String { timeSignature.tempoLabel(bpm: bpm, counting: beatCounting) }
    var dottedHint: String? {
        if timeSignature.isCompound && beatCounting == .grouped {
            return "每小节 \(beatsPerBar) 大拍 · 每拍含 3 个\(timeSignature.beatUnit.symbol)"
        }
        return timeSignature.dottedEquivalentLabel(bpm: bpm)
    }

    // MARK: - 传输

    func togglePlayback() {
        isRunning ? stop() : start()
    }

    func start() {
        guard !isRunning else { return }
        applyAllToEngine()
        engine.configurePractice(settings.practice.enabled ? settings.practice : nil)
        engine.start()
        isRunning = true
        updateIdleTimer()
        if settings.practice.enabled {
            playbackObservationTask?.cancel()
            playbackObservationTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard self?.isRunning == true else { return }
                    self?.refreshPracticeDisplay()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
    }

    func stop() {
        engine.stop()
        finishPlaybackUI()
    }

    private func finishPlaybackUI() {
        isRunning = false
        playbackObservationTask?.cancel()
        playbackObservationTask = nil
        playbackPosition = nil
        pendingPracticeAction = nil
        pendingPracticeRevision = nil
        updateIdleTimer()
    }

    private func refreshPracticeDisplay() {
        let position = engine.position()
        if let revision = pendingPracticeRevision,
           let applied = position?.practice?.actionRevision, applied >= revision {
            pendingPracticeAction = nil
            pendingPracticeRevision = nil
        }
        guard position?.bpm != playbackPosition?.bpm
                || position?.practice != playbackPosition?.practice
                || position?.isCountIn != playbackPosition?.isCountIn else { return }
        playbackPosition = position
    }

    func setPractice(_ configuration: TempoPracticeConfiguration) {
        guard !isRunning, configuration.isValid else { return }
        settings.practice = configuration.sanitized()
        persist()
    }

    func setPracticeEnabled(_ enabled: Bool) {
        guard !isRunning else { return }
        commitBPMEditing()
        var configuration = settings.practice
        configuration.enabled = enabled
        setPractice(configuration)
    }

    func requestPracticeAction(_ action: TempoPracticeAction) {
        guard isPracticeRunning, practiceProgress != nil, pendingPracticeAction == nil,
              let revision = engine.requestPracticeAction(action) else { return }
        pendingPracticeRevision = revision
        pendingPracticeAction = action
    }

    private var canEditRhythm: Bool {
        guard !isPracticeRunning else {
            show(banner: "请先停止渐进提速练习，再修改节奏参数")
            return false
        }
        return true
    }

    private func applyAllToEngine() {
        engine.setMeter(settings.timeSignature, counting: beatCounting, grouping: grouping, bpm: bpm)
        engine.setSubdivision(settings.subdivision)
        engine.setAccentEnabled(settings.accentEnabled)
        engine.setCountIn(settings.countInEnabled)
        engine.setTimbre(settings.timbre)
        engine.volume = Float(settings.volume)
    }

    // MARK: - 参数

    func beginBPMEditing() {
        guard canEditRhythm else { return }
        bpmDraft = "\(bpm)"
    }

    /// 提交输入框内容。空输入或非法输入视为取消，保留原值。
    func commitBPMEditing() {
        guard let draft = bpmDraft else { return }
        bpmDraft = nil
        guard let value = BPMInput.parse(draft) else { return }
        setBPM(value)
    }

    func cancelBPMEditing() {
        bpmDraft = nil
    }

    func setBPM(_ value: Int) {
        guard canEditRhythm else { return }
        let clamped = BPMInput.clamp(value)
        if settings.practice.enabled {
            settings.practice.startBPM = clamped
            settings.practice.targetBPM = max(clamped, settings.practice.targetBPM)
            engine.setBPM(clamped)
            persist()
            return
        }
        guard clamped != settings.bpm else { return }
        settings.bpm = clamped
        engine.setBPM(clamped)
        persist()
    }

    func adjustBPM(by delta: Int) {
        setBPM(bpm + delta)
    }

    func setTimeSignature(_ value: TimeSignature) {
        guard canEditRhythm else { return }
        commitBPMEditing()
        guard value != settings.timeSignature else { return }
        settings.timeSignature = value
        settings.beatCounting = value.isCompound ? .grouped : .written
        settings.grouping = 0
        applyMeter()
    }

    func setBeatCounting(_ value: BeatCounting) {
        guard canEditRhythm else { return }
        commitBPMEditing()
        guard timeSignature.isCompound, value != beatCounting else { return }
        let oldUnits = timeSignature.unitsPerBeat(beatCounting)
        let newUnits = timeSignature.unitsPerBeat(value)
        let converted = Int((Double(bpm * oldUnits) / Double(newUnits)).rounded())
        settings.beatCounting = value
        if settings.practice.enabled {
            settings.practice.startBPM = BPMInput.clamp(converted)
            settings.practice.targetBPM = max(settings.practice.startBPM, BPMInput.clamp(Int((Double(settings.practice.targetBPM * oldUnits) / Double(newUnits)).rounded())))
            settings.practice.increment = min(40, max(1, Int((Double(settings.practice.increment * oldUnits) / Double(newUnits)).rounded())))
        } else {
            settings.bpm = BPMInput.clamp(converted)
        }
        applyMeter()
        if converted != bpm { show(banner: "换算速度超出范围，已调整至 \(bpm) BPM") }
    }

    func setGrouping(_ value: Int) {
        guard canEditRhythm else { return }
        commitBPMEditing()
        let value = min(max(value, 0), timeSignature.groupingOptions.count - 1)
        guard grouping != value else { return }
        settings.grouping = value
        applyMeter()
    }

    private func applyMeter() {
        engine.setMeter(timeSignature, counting: beatCounting, grouping: grouping, bpm: bpm)
        notifyIfDeferred(barLevel: true)
        persist()
    }

    func setSubdivision(_ value: Subdivision) {
        guard canEditRhythm else { return }
        guard value != settings.subdivision else { return }
        settings.subdivision = value
        engine.setSubdivision(value)
        notifyIfDeferred(barLevel: true)
        persist()
    }

    func setAccentEnabled(_ value: Bool) {
        guard canEditRhythm else { return }
        guard value != settings.accentEnabled else { return }
        settings.accentEnabled = value
        engine.setAccentEnabled(value)
        notifyIfDeferred(barLevel: true)
        persist()
    }

    func setCountInEnabled(_ value: Bool) {
        settings.countInEnabled = value
        engine.setCountIn(value)
        persist()
    }

    func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        settings.volume = clamped
        engine.volume = Float(clamped)
        persist()
    }

    func setKeepAwake(_ value: Bool) {
        settings.keepAwake = value
        updateIdleTimer()
        persist()
    }

    func setTheme(_ theme: MetronomeAppearance) {
        guard theme != settings.theme else { return }
        settings.theme = theme
        persist()
    }

    func setSound(_ sound: Timbre) {
        guard sound != settings.timbre else { return }
        settings.timbre = sound
        engine.setTimbre(sound)
        persist()
        if isRunning { show(banner: "已选择声音，随后续节拍生效", duration: 1.5) }
    }

    func previewSound(_ sound: Timbre) {
        guard !isRunning else { return }
        engine.previewSound(sound)
    }

    // MARK: - 收藏

    private var currentRhythmSettings: MetronomeSettings {
        var current = settings
        current.bpm = bpm
        return current
    }
    var currentIsFavorite: Bool { favorites.items.contains { $0.matches(currentRhythmSettings) } }

    func saveFavorite() {
        commitBPMEditing()
        guard !currentIsFavorite else { return }
        guard favorites.add(currentRhythmSettings) else {
            show(banner: "已收藏 5 组，展开后长按某条收藏，可用当前设置覆盖")
            return
        }
        favorites.save()
    }

    func applyFavorite(_ favorite: FavoriteRhythm) {
        guard canEditRhythm else { return }
        commitBPMEditing()
        settings = favorite.applying(to: settings)
        settings.practice.enabled = false
        applyAllToEngine()
        persist()
        if isRunning {
            show(banner: "已切换收藏，速度随后续节拍生效，拍号、细分与重音随后续小节生效", duration: 2.5)
        }
    }

    func removeFavorite(_ favorite: FavoriteRhythm) {
        favorites.remove(id: favorite.id)
        favorites.save()
    }

    func updateFavorite(_ favorite: FavoriteRhythm) {
        commitBPMEditing()
        guard favorites.update(id: favorite.id, with: currentRhythmSettings) else {
            show(banner: "当前设置已存在于其他收藏中")
            return
        }
        favorites.save()
        show(banner: "已用当前设置覆盖收藏")
    }

    // MARK: - 辅助

    /// 播放中改动被延后时给出明确反馈，避免用户以为没点上。
    private func notifyIfDeferred(barLevel: Bool) {
        guard isRunning else { return }
        show(banner: barLevel ? "已设定，将在后续小节生效" : "已设定，将在后续节拍生效", duration: 1.4)
    }

    private func show(banner text: String, duration: Double = 3.0) {
        bannerTask?.cancel()
        banner = text
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.banner = nil }
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = settings.keepAwake && isRunning
    }

    func saveSettingsNow() {
        saveTask?.cancel()
        saveTask = nil
        SettingsStore.save(settings)
    }

    private func persist() {
        saveTask?.cancel()
        let snapshot = settings
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            SettingsStore.save(snapshot)
        }
    }
}
