import Foundation

/// 持久化节奏、练习方案及独立的外观和声音偏好。
struct MetronomeSettings: Codable, Equatable {
    var beatCounting: BeatCounting = .written
    var grouping: Int = 0
    var bpm: Int
    var timeSignature: TimeSignature
    var subdivision: Subdivision
    var volume: Double
    var theme: MetronomeAppearance = .icon
    var timbre: Timbre = .crystalTick
    var practice = TempoPracticeConfiguration()
    var accentEnabled: Bool
    var countInEnabled: Bool
    var keepAwake: Bool

    static let `default` = MetronomeSettings(bpm: 96,
                                             timeSignature: .fourFour,
                                             subdivision: .none,
                                             volume: 0.85,
                                             theme: .icon,
                                             accentEnabled: true,
                                             countInEnabled: true,
                                             keepAwake: false)

    /// 夹紧到合法区间，防止历史脏数据或异常写入导致界面卡死。
    func sanitized() -> MetronomeSettings {
        var copy = self
        copy.bpm = BPMInput.clamp(bpm)
        if !timeSignature.isCompound { copy.beatCounting = .written }
        copy.grouping = min(max(grouping, 0), timeSignature.groupingOptions.count - 1)
        copy.volume = min(max(volume, 0), 1)
        copy.practice = practice.sanitized()
        return copy
    }
}

// 缺少声音字段的旧主题数据按原搭配迁移，随后外观与声音独立保存。
extension MetronomeSettings {
    private enum CodingKeys: String, CodingKey {
        case bpm, timeSignature, subdivision, volume, theme, accentEnabled, countInEnabled, keepAwake, beatCounting, grouping, timbre, practice
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        beatCounting = try values.decodeIfPresent(BeatCounting.self, forKey: .beatCounting) ?? .written
        grouping = try values.decodeIfPresent(Int.self, forKey: .grouping) ?? 0
        bpm = try values.decode(Int.self, forKey: .bpm)
        timeSignature = try values.decode(TimeSignature.self, forKey: .timeSignature)
        subdivision = try values.decode(Subdivision.self, forKey: .subdivision)
        volume = try values.decode(Double.self, forKey: .volume)
        theme = (try values.decodeIfPresent(String.self, forKey: .theme)).flatMap(MetronomeAppearance.init(rawValue:)) ?? .icon
        let sound = try values.decodeIfPresent(String.self, forKey: .timbre)
        timbre = sound.flatMap(Timbre.legacy) ?? theme.legacyTimbre
        practice = try values.decodeIfPresent(TempoPracticeConfiguration.self, forKey: .practice) ?? TempoPracticeConfiguration()
        accentEnabled = try values.decode(Bool.self, forKey: .accentEnabled)
        countInEnabled = try values.decode(Bool.self, forKey: .countInEnabled)
        keepAwake = try values.decode(Bool.self, forKey: .keepAwake)
    }
}

enum SettingsStore {

    private static let key = "com.pianometronome.settings.v1"

    static func load(from defaults: UserDefaults = .standard) -> MetronomeSettings {
        guard let data = defaults.data(forKey: key),
              var decoded = try? JSONDecoder().decode(MetronomeSettings.self, from: data) else {
            return .default
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if object?["theme"] == nil {
            decoded.theme = .loadLegacy(from: defaults)
            if object?["timbre"] == nil { decoded.timbre = decoded.theme.legacyTimbre }
        }
        return decoded.sanitized()
    }

    static func save(_ settings: MetronomeSettings, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings.sanitized()) else { return }
        defaults.set(data, forKey: key)
    }
}
