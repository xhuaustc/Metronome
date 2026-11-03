import Foundation

/// 持久化的全部用户参数。只有这 8 个字段，没有设备标识、没有埋点。
struct MetronomeSettings: Codable, Equatable {
    var bpm: Int
    var timeSignature: TimeSignature
    var subdivision: Subdivision
    var volume: Double
    var timbre: Timbre
    var accentEnabled: Bool
    var countInEnabled: Bool
    var keepAwake: Bool

    static let `default` = MetronomeSettings(bpm: 96,
                                             timeSignature: .fourFour,
                                             subdivision: .none,
                                             volume: 0.85,
                                             timbre: .woodClick,
                                             accentEnabled: true,
                                             countInEnabled: true,
                                             keepAwake: false)

    /// 夹紧到合法区间，防止历史脏数据或异常写入导致界面卡死。
    func sanitized() -> MetronomeSettings {
        var copy = self
        copy.bpm = min(max(bpm, 30), 240)
        copy.volume = min(max(volume, 0), 1)
        return copy
    }
}

enum SettingsStore {

    private static let key = "com.pianometronome.settings.v1"

    static func load() -> MetronomeSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(MetronomeSettings.self, from: data) else {
            return .default
        }
        return decoded.sanitized()
    }

    static func save(_ settings: MetronomeSettings) {
        guard let data = try? JSONEncoder().encode(settings.sanitized()) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
