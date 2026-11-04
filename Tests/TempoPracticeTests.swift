import XCTest
@testable import MetronomeCore

final class TempoPracticeTests: XCTestCase {
    private func configuration(start: Int = 60, target: Int = 70, increment: Int = 4, bars: Int = 2) -> TempoPracticeConfiguration {
        var plan = TempoPracticeConfiguration()
        plan.enabled = true
        plan.startBPM = start
        plan.targetBPM = target
        plan.increment = increment
        plan.barsPerStep = bars
        return plan
    }

    func testRampsOnlyAtExactBarBoundariesAndExcludesCountIn() throws {
        let planner = SchedulePlanner(sampleRate: 600, bpm: 96, timeSignature: .twoFour)
        planner.configurePractice(configuration())
        planner.start(atFrame: 0, countIn: true)
        let points = planner.plan(upTo: 8000)
        let barStarts = points.filter { $0.beat == 0 }
        let expected = [60, 60, 60, 64, 64, 68, 68, 70]
        for (index, point) in barStarts.prefix(expected.count).enumerated() {
            XCTAssertEqual(try XCTUnwrap(planner.position(at: point.frame)).bpm, expected[index])
        }
        XCTAssertTrue(barStarts[0].isCountIn)
        XCTAssertFalse(barStarts[1].isCountIn)
        XCTAssertEqual(barStarts[1].frame, 1200)
        XCTAssertEqual(barStarts[3].frame, 3600)
        for (left, right) in zip(points, points.dropFirst()) {
            let bpm = try XCTUnwrap(planner.position(at: left.frame)).bpm
            XCTAssertEqual(right.frame - left.frame, 600 * 60 / Double(bpm), accuracy: 1e-8)
        }
    }

    func testHoldResumeAndBackoffUseFollowingBarAndDoNotRewriteHistory() throws {
        let planner = SchedulePlanner(sampleRate: 600, bpm: 60, timeSignature: .twoFour)
        planner.configurePractice(configuration(bars: 1))
        planner.start(atFrame: 0, countIn: false)
        _ = planner.plan(upTo: 1)
        let original = try XCTUnwrap(planner.position(at: 0))
        planner.requestPracticeAction(.hold)
        _ = planner.plan(upTo: 1201)
        XCTAssertEqual(planner.position(at: 1200)?.bpm, 60)
        XCTAssertEqual(planner.position(at: 1200)?.practice?.isHolding, true)
        XCTAssertEqual(planner.position(at: 0)?.bpm, original.bpm)
        XCTAssertEqual(planner.position(at: 0)?.practice, original.practice)
        planner.requestPracticeAction(.resume)
        _ = planner.plan(upTo: 2401)
        XCTAssertEqual(planner.position(at: 2400)?.bpm, 60)
        XCTAssertEqual(planner.position(at: 2400)?.practice?.isHolding, false)
        _ = planner.plan(upTo: 3601)
        XCTAssertEqual(planner.position(at: 3600)?.bpm, 64)
        planner.requestPracticeAction(.stepBack)
        let nextBar = 3600 + 2 * 600 * 60 / 64.0
        _ = planner.plan(upTo: nextBar + 1)
        XCTAssertEqual(planner.position(at: nextBar)?.bpm, 60)
        XCTAssertEqual(planner.position(at: nextBar)?.practice?.isHolding, true)
    }

    func testActionAcknowledgmentFollowsAudibleBarDespiteLookahead() throws {
        let planner = SchedulePlanner(sampleRate: 600, bpm: 60, timeSignature: .twoFour)
        planner.configurePractice(configuration(bars: 1))
        planner.start(atFrame: 0, countIn: false)
        _ = planner.plan(upTo: 1801) // 已排入下一小节，用户仍听到第一小节。
        let revision = try XCTUnwrap(planner.requestPracticeAction(.hold, atFrame: 300))
        let next = planner.plan(upTo: 4000)
        let boundary = try XCTUnwrap(next.first { $0.beat == 0 && planner.position(at: $0.frame)?.practice?.actionRevision == revision }).frame
        XCTAssertEqual(planner.position(at: 300)?.practice?.actionRevision, 0)
        XCTAssertEqual(planner.position(at: boundary - 1)?.practice?.actionRevision, 0)
        XCTAssertEqual(planner.position(at: boundary)?.practice?.actionRevision, revision)
        XCTAssertEqual(planner.position(at: boundary)?.practice?.isHolding, true)
        let resume = try XCTUnwrap(planner.requestPracticeAction(.resume, atFrame: boundary))
        XCTAssertGreaterThan(resume, revision)
        let resumed = planner.plan(upTo: 6000)
        let resumedBoundary = try XCTUnwrap(resumed.first { $0.beat == 0 && planner.position(at: $0.frame)?.practice?.actionRevision == resume }).frame
        XCTAssertEqual(planner.position(at: boundary)?.practice?.actionRevision, revision)
        XCTAssertEqual(planner.position(at: resumedBoundary)?.practice?.actionRevision, resume)
        XCTAssertEqual(planner.position(at: resumedBoundary)?.practice?.isHolding, false)
        planner.stop()
        XCTAssertNil(planner.requestPracticeAction(.hold))
        planner.start(atFrame: 7000, countIn: false)
        _ = planner.plan(upTo: 7001)
        XCTAssertEqual(planner.position(at: 7000)?.practice?.actionRevision, 0)
    }

    func testPartialFinalStepBackReturnsToPreviousActualStage() throws {
        let planner = SchedulePlanner(sampleRate: 600, bpm: 60, timeSignature: .twoFour)
        planner.configurePractice(configuration(start: 60, target: 65, increment: 4, bars: 1))
        planner.start(atFrame: 0, countIn: false)
        var starts: [SoundPoint] = []
        // 每次只生成一小节的第一拍，避免把用户操作后的边界提前排入队列。
        while starts.count < 3 {
            let next = planner.plan(upTo: 10000, maxPoints: 1)
            if next.first?.beat == 0 { starts.append(next[0]) }
        }
        XCTAssertEqual(planner.position(at: starts[2].frame)?.bpm, 65)
        XCTAssertEqual(planner.position(at: starts[2].frame)?.practice?.reachedTarget, true)
        planner.requestPracticeAction(.stepBack)
        let nextBar = starts[2].frame + 2 * 600 * 60 / 65.0
        _ = planner.plan(upTo: nextBar + 1)
        XCTAssertEqual(planner.position(at: nextBar)?.bpm, 64)
        XCTAssertEqual(planner.position(at: nextBar)?.practice?.isHolding, true)
    }

    func testBackoffUsesAudibleStageWhenLookaheadIsSeveralStagesAhead() throws {
        let planner = SchedulePlanner(sampleRate: 600, bpm: 60, timeSignature: .twoFour)
        planner.configurePractice(configuration(target: 100, increment: 10, bars: 1))
        planner.start(atFrame: 0, countIn: false)
        _ = planner.plan(upTo: 3300)
        XCTAssertEqual(planner.position(at: 1300)?.bpm, 70)
        XCTAssertGreaterThan(planner.bpm, 70)
        let old = try XCTUnwrap(planner.position(at: 1300))
        planner.requestPracticeAction(.stepBack, atFrame: 1300)
        let points = planner.plan(upTo: 5000)
        let heldBar = try XCTUnwrap(points.first { $0.beat == 0 })
        XCTAssertEqual(planner.position(at: heldBar.frame)?.bpm, 60)
        XCTAssertEqual(planner.position(at: heldBar.frame)?.practice?.isHolding, true)
        XCTAssertEqual(planner.position(at: 1300), old)
    }

    func testEveryMeterAndSubdivisionCountsWholeBarsAtTempoExtremes() throws {
        for meter in TimeSignature.allCases {
            for counting in BeatCounting.allCases {
                for subdivision in Subdivision.allCases {
                    let planner = SchedulePlanner(sampleRate: 48000, bpm: 96, timeSignature: meter, subdivision: subdivision, beatCounting: counting)
                    planner.configurePractice(configuration(start: 399, target: 400, increment: 4, bars: 1))
                    planner.start(atFrame: 100, countIn: false)
                    let beats = meter.beatCount(counting)
                    let boundary = 100 + Double(beats) * 48000 * 60 / 399
                    let points = planner.plan(upTo: boundary + 1)
                    XCTAssertEqual(points.count, beats * subdivision.partsPerBeat + 1)
                    let actualBoundary = try XCTUnwrap(points.last).frame
                    XCTAssertEqual(actualBoundary, boundary, accuracy: 1e-6)
                    XCTAssertEqual(planner.position(at: actualBoundary)?.bpm, 400)
                    XCTAssertEqual(planner.position(at: actualBoundary)?.practice?.reachedTarget, true)
                    for (left, right) in zip(points, points.dropFirst()) {
                        XCTAssertGreaterThan(right.frame, left.frame)
                    }
                }
            }
        }
    }

    func testStopAndRestartResetPracticeAndOrdinaryModeHasNoProgress() throws {
        let planner = SchedulePlanner(sampleRate: 600, bpm: 96, timeSignature: .twoFour)
        planner.configurePractice(configuration(bars: 1))
        planner.start(atFrame: 0, countIn: false)
        _ = planner.plan(upTo: 3600)
        planner.requestPracticeAction(.hold)
        planner.stop()
        planner.start(atFrame: 5000, countIn: false)
        _ = planner.plan(upTo: 5001)
        XCTAssertEqual(planner.position(at: 5000)?.bpm, 60)
        XCTAssertEqual(planner.position(at: 5000)?.practice?.stageBar, 1)
        XCTAssertEqual(planner.position(at: 5000)?.practice?.isHolding, false)
        planner.stop()
        planner.configurePractice(nil)
        planner.setBPM(96)
        planner.start(atFrame: 6000, countIn: false)
        _ = planner.plan(upTo: 6001)
        XCTAssertNil(planner.position(at: 6000)?.practice)
        XCTAssertEqual(planner.position(at: 6000)?.bpm, 96)
    }

    func testTargetEqualToStartRemainsStableAndPlanPersistsWithoutProgress() throws {
        let suite = "TempoPracticeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = MetronomeSettings.default
        settings.practice = configuration(start: 400, target: 400, bars: 1)
        settings.theme = .walnut
        settings.timbre = .electroPulse
        SettingsStore.save(settings, to: defaults)
        XCTAssertEqual(SettingsStore.load(from: defaults), settings)
        let planner = SchedulePlanner(sampleRate: 600, bpm: 96, timeSignature: .threeFour)
        planner.configurePractice(settings.practice)
        planner.start(atFrame: 0, countIn: false)
        let points = planner.plan(upTo: 6000)
        for point in points {
            XCTAssertEqual(planner.position(at: point.frame)?.bpm, 400)
            XCTAssertEqual(planner.position(at: point.frame)?.practice?.reachedTarget, true)
        }
    }

    func testInvalidPlanIsSanitizedAndLegacyFavoritesPreserveSoundAndPlan() throws {
        var plan = configuration(start: 999, target: -1, increment: 0, bars: 99)
        XCTAssertFalse(plan.isValid)
        plan = plan.sanitized()
        XCTAssertTrue(plan.isValid)
        XCTAssertEqual(plan.startBPM, 400)
        XCTAssertEqual(plan.targetBPM, 400)
        XCTAssertEqual(plan.increment, 1)
        XCTAssertEqual(plan.barsPerStep, 32)
        var settings = MetronomeSettings.default
        settings.practice = configuration()
        settings.timbre = .feltHammer
        settings.theme = .graphite
        let favorite = FavoriteRhythm(settings: .default)
        let applied = favorite.applying(to: settings)
        XCTAssertEqual(applied.timbre, settings.timbre)
        XCTAssertEqual(applied.theme, settings.theme)
        XCTAssertEqual(applied.practice, settings.practice)
    }
}
