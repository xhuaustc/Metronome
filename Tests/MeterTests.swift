import XCTest
@testable import MetronomeCore

final class MeterTests: XCTestCase {
    func testAllMetersHaveValidGroupingAndOneDownbeat() {
        XCTAssertEqual(TimeSignature.allCases.count, 14)
        for meter in TimeSignature.allCases {
            for grouping in meter.groupingOptions.indices {
                XCTAssertEqual(meter.groups(grouping: grouping).reduce(0, +), meter.numerator)
                for counting in BeatCounting.allCases {
                    let accents = (0..<meter.beatCount(counting)).map { meter.accent(atBeat: $0, counting: counting, grouping: grouping) }
                    XCTAssertEqual(accents.filter { $0 == .strong }.count, 1)
                }
            }
        }
        XCTAssertEqual(TimeSignature.twoTwo.beatUnit, .half)
        XCTAssertEqual(TimeSignature.sevenEight.groups(grouping: 2), [2, 3, 2])
        XCTAssertEqual((0..<5).map { TimeSignature.fiveFour.accent(atBeat: $0, grouping: 1) }, [.strong, .normal, .normal, .group, .normal])
    }

    func testCompoundMainBeatsAndTripletsMatchMusicalUnits() throws {
        for (meter, beats, unit) in [(TimeSignature.sixEight, 2, BeatUnit.dottedQuarter), (.nineEight, 3, .dottedQuarter), (.twelveEight, 4, .dottedQuarter), (.sixFour, 2, .dottedHalf)] {
            XCTAssertEqual(meter.unit(.grouped), unit)
            XCTAssertEqual(meter.beatCount(.grouped), beats)
            let planner = SchedulePlanner(sampleRate: 48000, bpm: 120, timeSignature: meter, subdivision: .three, beatCounting: .grouped)
            planner.start(atFrame: 0, countIn: true)
            let barFrames = Double(beats) * 24000
            let points = planner.plan(upTo: barFrames)
            XCTAssertEqual(points.count, beats * 3)
            for (i, point) in points.enumerated() {
                XCTAssertEqual(point.frame, Double(i) * 8000, accuracy: 1e-8)
                XCTAssertEqual(point.beat, i / 3)
                XCTAssertEqual(point.part, i % 3)
                XCTAssertTrue(point.isCountIn)
            }
            let next = planner.plan(upTo: barFrames + 1)
            XCTAssertEqual(next.first?.barNumber, 1)
            XCTAssertEqual(next.first?.beat, 0)
            let old = try XCTUnwrap(planner.position(at: barFrames - 4000))
            XCTAssertEqual(old.beatsPerBar, beats)
            XCTAssertEqual(old.partsPerBeat, 3)
        }
    }

    func testCountingAndConvertedTempoChangeTogetherAtBarBoundary() throws {
        let planner = SchedulePlanner(sampleRate: 48000, bpm: 180, timeSignature: .sixEight)
        planner.start(atFrame: 0, countIn: false)
        _ = planner.plan(upTo: 1)
        let original = try XCTUnwrap(planner.position(at: 0))
        planner.setMeter(.sixEight, counting: .grouped, grouping: 0, bpm: 60)
        XCTAssertFalse(planner.hasPendingTempoChange)
        XCTAssertTrue(planner.hasPendingBarChange)
        let oldBar = planner.plan(upTo: 96000)
        XCTAssertEqual(oldBar.map(\.frame), [16000, 32000, 48000, 64000, 80000])
        XCTAssertEqual(planner.position(at: 0)?.pendulumPhase, original.pendulumPhase)
        XCTAssertEqual(planner.position(at: 0)?.beatsPerBar, original.beatsPerBar)
        XCTAssertEqual(planner.position(at: 95999)?.beatsPerBar, 6)
        let next = planner.plan(upTo: 192000)
        XCTAssertEqual(next.map(\.frame), [96000, 144000])
        XCTAssertEqual(next.map(\.beat), [0, 1])
        XCTAssertEqual(planner.position(at: 96000)?.beatsPerBar, 2)
        XCTAssertEqual(planner.bpm, 60)
        XCTAssertFalse(planner.hasPendingBarChange)
    }

    func testLaterTempoEditDoesNotRestoreStaleConvertedTempo() {
        let planner = SchedulePlanner(sampleRate: 48000, bpm: 180, timeSignature: .sixEight)
        planner.start(atFrame: 0, countIn: false)
        _ = planner.plan(upTo: 1)
        planner.setMeter(.sixEight, counting: .grouped, grouping: 0, bpm: 60)
        planner.setBPM(90)
        _ = planner.plan(upTo: 96001)
        XCTAssertEqual(planner.bpm, 90)
        XCTAssertEqual(planner.beatCounting, .grouped)
        planner.stop()
        XCTAssertFalse(planner.hasPendingBarChange)
    }

    func testNewTempoExtremesAndFourPartSubdivisionsRemainOrdered() {
        for bpm in [20, 400] {
            for signature in TimeSignature.allCases {
                let planner = SchedulePlanner(sampleRate: 48000, bpm: bpm, timeSignature: signature, subdivision: .four, beatCounting: .grouped)
                planner.start(atFrame: 1234, countIn: false)
                let points = planner.plan(upTo: 1234 + 48000 * 60, maxPoints: 2048)
                XCTAssertEqual(points.count, bpm * 4)
                for (index, point) in points.enumerated() {
                    XCTAssertEqual(point.frame, 1234 + Double(index) * 48000 * 60 / Double(bpm) / 4, accuracy: 1e-6)
                }
            }
        }
    }

    func testLegacySettingsAndFavoritesPreserveWrittenBeatAndIdentity() throws {
        var saved = MetronomeSettings.default
        saved.timeSignature = .sixEight
        saved.bpm = 96
        let favorite = FavoriteRhythm(settings: saved)
        func legacy(_ data: Data) throws -> Data {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            json.removeValue(forKey: "beatCounting")
            json.removeValue(forKey: "grouping")
            return try JSONSerialization.data(withJSONObject: json)
        }
        let decoded = try JSONDecoder().decode(MetronomeSettings.self, from: legacy(JSONEncoder().encode(saved)))
        let decodedFavorite = try JSONDecoder().decode(FavoriteRhythm.self, from: legacy(JSONEncoder().encode(favorite)))
        XCTAssertEqual(decoded.bpm, 96)
        XCTAssertEqual(decoded.beatCounting, .written)
        XCTAssertEqual(decodedFavorite.id, favorite.id)
        XCTAssertEqual(decodedFavorite.applying(to: .default), saved)
    }

    func testNewFavoritesPersistCountingGroupingAndExtendedTempo() throws {
        let suite = "MeterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var favorites = RhythmFavorites()
        var settings = MetronomeSettings.default
        settings.timeSignature = .twelveEight
        settings.beatCounting = .grouped
        settings.bpm = 400
        XCTAssertTrue(favorites.add(settings))
        settings.beatCounting = .written
        XCTAssertTrue(favorites.add(settings))
        settings.timeSignature = .sevenEight
        settings.grouping = 2
        settings.bpm = 20
        XCTAssertTrue(favorites.add(settings))
        favorites.save(to: defaults)
        let loaded = RhythmFavorites.load(from: defaults)
        XCTAssertEqual(loaded.items, favorites.items)
        XCTAssertEqual(loaded.items.last?.applying(to: .default).grouping, 2)
    }
}
