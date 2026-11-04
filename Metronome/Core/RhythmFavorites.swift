import Foundation

/// 收藏只保存节奏参数，不改变主题、音量、预备拍或屏幕常亮偏好。
struct FavoriteRhythm: Codable, Equatable, Identifiable {
    let id: UUID
    let beatCounting: BeatCounting
    let grouping: Int
    let bpm: Int
    let timeSignature: TimeSignature
    let subdivision: Subdivision
    let accentEnabled: Bool

    init(settings: MetronomeSettings, id: UUID = UUID()) {
        self.id = id
        let settings = settings.sanitized()
        beatCounting = settings.beatCounting
        grouping = settings.grouping
        bpm = settings.bpm
        timeSignature = settings.timeSignature
        subdivision = settings.subdivision
        accentEnabled = settings.accentEnabled
    }

    func applying(to settings: MetronomeSettings) -> MetronomeSettings {
        var result = settings
        result.beatCounting = beatCounting
        result.grouping = grouping
        result.bpm = bpm
        result.timeSignature = timeSignature
        result.subdivision = subdivision
        result.accentEnabled = accentEnabled
        return result.sanitized()
    }

    func matches(_ settings: MetronomeSettings) -> Bool {
        applying(to: settings) == settings.sanitized()
    }
}

extension FavoriteRhythm {
    private enum CodingKeys: String, CodingKey { case id, bpm, timeSignature, subdivision, accentEnabled, beatCounting, grouping }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        bpm = try values.decode(Int.self, forKey: .bpm)
        timeSignature = try values.decode(TimeSignature.self, forKey: .timeSignature)
        subdivision = try values.decode(Subdivision.self, forKey: .subdivision)
        accentEnabled = try values.decode(Bool.self, forKey: .accentEnabled)
        beatCounting = try values.decodeIfPresent(BeatCounting.self, forKey: .beatCounting) ?? .written
        grouping = try values.decodeIfPresent(Int.self, forKey: .grouping) ?? 0
    }
}

struct RhythmFavorites: Codable {
    static let capacity = 5
    private static let key = "com.pianometronome.favorites.v1"
    private(set) var items: [FavoriteRhythm] = []

    @discardableResult
    mutating func add(_ settings: MetronomeSettings) -> Bool {
        guard items.count < Self.capacity, !items.contains(where: { $0.matches(settings) }) else { return false }
        items.append(FavoriteRhythm(settings: settings))
        return true
    }

    mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    @discardableResult
    mutating func update(id: UUID, with settings: MetronomeSettings) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }),
              !items.contains(where: { $0.id != id && $0.matches(settings) }) else { return false }
        items[index] = FavoriteRhythm(settings: settings, id: id)
        return true
    }

    static func load(from defaults: UserDefaults = .standard) -> RhythmFavorites {
        guard let data = defaults.data(forKey: key),
              var decoded = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        decoded.items = Array(decoded.items.prefix(capacity)).filter { BPMInput.range.contains($0.bpm) }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
