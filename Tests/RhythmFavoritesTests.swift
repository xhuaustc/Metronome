import XCTest
@testable import MetronomeCore

final class RhythmFavoritesTests: XCTestCase {
    func testUpdateFullFavoritesPreservesIdentityOrderAndPersistsAllRhythmSettings() throws {
        let suite = "RhythmFavoritesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var favorites = RhythmFavorites()
        for bpm in [60, 80, 100, 120, 140] {
            var settings = MetronomeSettings.default
            settings.bpm = bpm
            XCTAssertTrue(favorites.add(settings))
        }
        let original = favorites.items
        var updated = MetronomeSettings.default
        updated.bpm = 168
        updated.timeSignature = .sixEight
        updated.subdivision = .three
        updated.theme = .walnut
        updated.accentEnabled = false
        XCTAssertTrue(favorites.update(id: original[2].id, with: updated))
        XCTAssertEqual(favorites.items.map(\.id), original.map(\.id))
        XCTAssertEqual(favorites.items.map(\.bpm), [60, 80, 168, 120, 140])
        XCTAssertTrue(favorites.items[2].matches(updated))
        for index in [0, 1, 3, 4] {
            XCTAssertEqual(favorites.items[index], original[index])
        }
        favorites.save(to: defaults)
        XCTAssertEqual(RhythmFavorites.load(from: defaults).items, favorites.items)
    }

    func testUpdateRejectsDuplicateAndMissingIDWithoutChangingFavorites() {
        var favorites = RhythmFavorites()
        var settings = MetronomeSettings.default
        favorites.add(settings)
        settings.bpm += 10
        favorites.add(settings)
        let original = favorites.items
        settings.volume = 0.2
        settings.keepAwake.toggle()
        settings.theme = .ivory
        XCTAssertFalse(favorites.update(id: original[0].id, with: settings))
        XCTAssertFalse(favorites.update(id: UUID(), with: settings))
        XCTAssertEqual(favorites.items, original)
        XCTAssertTrue(favorites.update(id: original[1].id, with: settings))
        XCTAssertEqual(favorites.items, original)
    }

    func testLimitsToFiveWithoutReplacingExistingFavorites() {
        var favorites = RhythmFavorites()
        for bpm in [60, 80, 100, 120, 140] {
            var settings = MetronomeSettings.default
            settings.bpm = bpm
            XCTAssertTrue(favorites.add(settings))
        }
        var sixth = MetronomeSettings.default
        sixth.bpm = 160
        XCTAssertFalse(favorites.add(sixth))
        XCTAssertEqual(favorites.items.map(\.bpm), [60, 80, 100, 120, 140])
        favorites.remove(id: favorites.items[2].id)
        XCTAssertTrue(favorites.add(sixth))
        XCTAssertEqual(favorites.items.map(\.bpm), [60, 80, 120, 140, 160])
    }

    func testDuplicateIgnoresPlaybackPreferencesButDistinguishesRhythms() {
        var favorites = RhythmFavorites()
        var settings = MetronomeSettings.default
        XCTAssertTrue(favorites.add(settings))
        settings.volume = 0.2
        settings.keepAwake.toggle()
        settings.countInEnabled.toggle()
        XCTAssertFalse(favorites.add(settings))
        settings.timeSignature = .sixEight
        XCTAssertTrue(favorites.add(settings))
        settings.subdivision = .three
        XCTAssertTrue(favorites.add(settings))
        settings.theme = .graphite
        XCTAssertFalse(favorites.add(settings))
        settings.accentEnabled.toggle()
        XCTAssertTrue(favorites.add(settings))
    }

    func testRecallRestoresRhythmAndPreservesPlaybackPreferences() {
        var saved = MetronomeSettings.default
        saved.bpm = 168
        saved.timeSignature = .sixEight
        saved.subdivision = .three
        saved.theme = .walnut
        saved.accentEnabled = false
        let favorite = FavoriteRhythm(settings: saved)
        var current = MetronomeSettings.default
        current.volume = 0.1
        current.countInEnabled = false
        current.keepAwake = true
        let applied = favorite.applying(to: current)
        XCTAssertEqual(applied.bpm, 168)
        XCTAssertEqual(applied.timeSignature, .sixEight)
        XCTAssertEqual(applied.subdivision, .three)
        XCTAssertEqual(applied.theme, current.theme)
        XCTAssertEqual(applied.timbre, current.timbre)
        XCTAssertFalse(applied.accentEnabled)
        XCTAssertEqual(applied.volume, 0.1)
        XCTAssertFalse(applied.countInEnabled)
        XCTAssertTrue(applied.keepAwake)
        XCTAssertTrue(favorite.matches(applied))
    }

    func testFavoritesSurviveReloadAndRemoval() throws {
        let suite = "RhythmFavoritesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(RhythmFavorites.load(from: defaults).items.isEmpty)
        var favorites = RhythmFavorites()
        favorites.add(.default)
        favorites.save(to: defaults)
        var reloaded = RhythmFavorites.load(from: defaults)
        XCTAssertEqual(reloaded.items, favorites.items)
        reloaded.remove(id: try XCTUnwrap(reloaded.items.first).id)
        reloaded.save(to: defaults)
        XCTAssertTrue(RhythmFavorites.load(from: defaults).items.isEmpty)
    }
}
