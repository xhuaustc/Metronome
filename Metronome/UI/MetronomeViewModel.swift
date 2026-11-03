import SwiftUI
import UIKit

@MainActor
final class MetronomeViewModel: ObservableObject {

    @Published private(set) var settings: MetronomeSettings
    @Published private(set) var isRunning = false
    @Published var banner: String?

    /// 非 nil 表示 BPM 正处于输入态。放在 ViewModel 而不是视图局部，
    /// 是为了让键盘工具栏、空白点击、失焦三条路径都能拿到同一份草稿。
    @Published var bpmDraft: String?

    let engine: MetronomeEngine

    private var saveTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    init(engine: MetronomeEngine = MetronomeEngine()) {
        self.engine = engine
        self.settings = SettingsStore.load()
        applyAllToEngine()

        engine.onInterruptionBegan = { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.updateIdleTimer()
            self.show(banner: "已被系统音频中断，已复位到第一拍")
        }

        engine.onEngineFailed = { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.updateIdleTimer()
            self.show(banner: "音频引擎已重置，请重新开始")
        }
    }

    // MARK: - 只读访问

    var bpm: Int { settings.bpm }
    var timeSignature: TimeSignature { settings.timeSignature }
    var subdivision: Subdivision { settings.subdivision }
    var timbre: Timbre { settings.timbre }
    var accentEnabled: Bool { settings.accentEnabled }
    var countInEnabled: Bool { settings.countInEnabled }
    var keepAwake: Bool { settings.keepAwake }
    var volume: Double { settings.volume }

    var tempoLabel: String { settings.timeSignature.tempoLabel(bpm: settings.bpm) }
    var dottedHint: String? { settings.timeSignature.dottedEquivalentLabel(bpm: settings.bpm) }

    // MARK: - 传输

    func togglePlayback() {
        isRunning ? stop() : start()
    }

    func start() {
        guard !isRunning else { return }
        applyAllToEngine()
        engine.start()
        isRunning = true
        updateIdleTimer()
    }

    func stop() {
        engine.stop()
        isRunning = false
        updateIdleTimer()
    }

    private func applyAllToEngine() {
        engine.setBPM(settings.bpm)
        engine.setTimeSignature(settings.timeSignature)
        engine.setSubdivision(settings.subdivision)
        engine.setAccentEnabled(settings.accentEnabled)
        engine.setCountIn(settings.countInEnabled)
        engine.setTimbre(settings.timbre)
        engine.volume = Float(settings.volume)
    }

    // MARK: - 参数

    func beginBPMEditing() {
        bpmDraft = "\(settings.bpm)"
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
        let clamped = min(max(value, 30), 240)
        guard clamped != settings.bpm else { return }
        settings.bpm = clamped
        engine.setBPM(clamped)
        persist()
    }

    func adjustBPM(by delta: Int) {
        setBPM(settings.bpm + delta)
    }

    func setTimeSignature(_ value: TimeSignature) {
        guard value != settings.timeSignature else { return }
        settings.timeSignature = value
        engine.setTimeSignature(value)
        notifyIfDeferred(barLevel: true)
        persist()
    }

    func setSubdivision(_ value: Subdivision) {
        guard value != settings.subdivision else { return }
        settings.subdivision = value
        engine.setSubdivision(value)
        notifyIfDeferred(barLevel: true)
        persist()
    }

    func setAccentEnabled(_ value: Bool) {
        guard value != settings.accentEnabled else { return }
        settings.accentEnabled = value
        engine.setAccentEnabled(value)
        notifyIfDeferred(barLevel: true)
        persist()
    }

    func setTimbre(_ value: Timbre) {
        guard value != settings.timbre else { return }
        settings.timbre = value
        engine.setTimbre(value)
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

    // MARK: - 辅助

    /// 播放中改动被延后时给出明确反馈，避免用户以为没点上。
    private func notifyIfDeferred(barLevel: Bool) {
        guard isRunning else { return }
        show(banner: barLevel ? "已设定，下一小节生效" : "已设定，下一拍生效", duration: 1.4)
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
