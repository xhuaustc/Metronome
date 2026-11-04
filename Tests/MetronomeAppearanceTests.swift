import XCTest
@testable import MetronomeCore

final class MetronomeAppearanceTests: XCTestCase {
    func testEveryAppearanceAndSoundCombinationPersists() throws {
        let suite = "MetronomeAppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(SettingsStore.load(from: defaults).theme, .icon)
        XCTAssertEqual(MetronomeAppearance.allCases.map(\.legacyTimbre), [.crystalTick, .woodKnock, .feltHammer, .electroPulse])
        var settings = MetronomeSettings.default
        settings.bpm = 168
        settings.timeSignature = .sixEight
        for theme in MetronomeAppearance.allCases {
            settings.theme = theme
            for sound in Timbre.allCases {
                settings.timbre = sound
                SettingsStore.save(settings, to: defaults)
                XCTAssertEqual(SettingsStore.load(from: defaults), settings)
                XCTAssertEqual(SettingsStore.load(from: defaults).timbre, sound)
                XCTAssertEqual(SettingsStore.load(from: defaults).theme, theme)
            }
        }
    }

    func testLegacyStyleMigratesWithoutLosingRhythmSettings() throws {
        let suite = "MetronomeAppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = MetronomeSettings.default
        settings.bpm = 168
        settings.volume = 0.25
        settings.timeSignature = .sixEight
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        legacy.removeValue(forKey: "theme")
        legacy["timbre"] = "beep"
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "com.pianometronome.settings.v1")
        defaults.set("ivory", forKey: "com.pianometronome.appearance.v1")
        let migrated = SettingsStore.load(from: defaults)
        XCTAssertEqual(migrated.theme, .ivory)
        XCTAssertEqual(migrated.timbre, .crystalTick)
        XCTAssertEqual(migrated.bpm, 168)
        XCTAssertEqual(migrated.volume, 0.25)
        XCTAssertEqual(migrated.timeSignature, .sixEight)
        SettingsStore.save(migrated, to: defaults)
        defaults.set("graphite", forKey: "com.pianometronome.appearance.v1")
        XCTAssertEqual(SettingsStore.load(from: defaults).theme, .ivory, "迁移后的主题优先于旧外观键")
    }

    func testBoundThemeDataMigratesToItsPreviousSound() throws {
        for theme in MetronomeAppearance.allCases {
            var settings = MetronomeSettings.default
            settings.theme = theme
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
            json.removeValue(forKey: "timbre")
            json.removeValue(forKey: "practice")
            let migrated = try JSONDecoder().decode(MetronomeSettings.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(migrated.theme, theme)
            XCTAssertEqual(migrated.timbre, theme.legacyTimbre)
            XCTAssertFalse(migrated.practice.enabled)
        }
    }

    func testUnknownThemeFallsBackWithoutResettingTempo() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(MetronomeSettings.default)) as? [String: Any])
        json["theme"] = "future-theme"
        json["bpm"] = 144
        let settings = try JSONDecoder().decode(MetronomeSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(settings.theme, .icon)
        XCTAssertEqual(settings.bpm, 144)
    }

    func testLegacyFavoritesIgnoreSavedAppearanceAndKeepRhythm() throws {
        var saved = MetronomeSettings.default
        saved.bpm = 168
        saved.timeSignature = .sixEight
        saved.subdivision = .three
        saved.accentEnabled = false
        let original = FavoriteRhythm(settings: saved)
        for legacyFields in [["theme": "walnut"], ["timbre": "woodClick"], ["timbre": "woodblock"], ["timbre": "beep"]] {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            for (key, value) in legacyFields { json[key] = value }
            let decoded = try JSONDecoder().decode(FavoriteRhythm.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(decoded, original)
            for theme in MetronomeAppearance.allCases {
                var current = MetronomeSettings.default
                current.theme = theme
                let applied = decoded.applying(to: current)
                XCTAssertEqual(applied.theme, theme)
                XCTAssertEqual(applied.timbre, current.timbre)
                XCTAssertTrue(decoded.matches(applied))
            }
            let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
            XCTAssertNil(encoded["theme"])
            XCTAssertNil(encoded["timbre"])
        }
    }
}
