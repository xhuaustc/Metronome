import XCTest
@testable import MetronomeCore

final class SchedulePlannerTests: XCTestCase {

    let sampleRate = 44100.0

    // MARK: - 稳定性

    /// 30 分钟连续运行，第 n 拍必须精确落在 n * framesPerBeat 上，不允许累积漂移。
    func testThirtyMinutesNoDrift() {
        let planner = SchedulePlanner(sampleRate: sampleRate, bpm: 120, timeSignature: .fourFour)
        planner.start(atFrame: 0, countIn: false)

        let framesPerBeat = sampleRate * 60.0 / 120.0  // 22050
        let totalFrames = 30.0 * 60.0 * sampleRate
        var points: [SoundPoint] = []

        var cursor = 0.0
        while cursor < totalFrames {
            cursor += 0.1 * sampleRate
            points.append(contentsOf: planner.plan(upTo: cursor))
        }

        XCTAssertEqual(points.count, 3600, "30 分钟 @120BPM 应为 3600 拍")

        var maxError = 0.0
        for (index, point) in points.enumerated() {
            let expected = Double(index) * framesPerBeat
            maxError = max(maxError, abs(point.frame - expected))
        }
        XCTAssertLessThan(maxError, 1e-6, "累积漂移应远小于 1 个采样帧，实测 \(maxError) 帧")
    }

    /// 各档速度下相邻间隔必须严格相等。
    func testIntervalUniformAcrossTempi() {
        for bpm in [30, 60, 96, 120, 177, 240] {
            let planner = SchedulePlanner(sampleRate: sampleRate, bpm: bpm, timeSignature: .fourFour)
            planner.start(atFrame: 0, countIn: false)
            let points = planner.plan(upTo: sampleRate * 60, maxPoints: 4096)
            XCTAssertGreaterThan(points.count, 3)

            let expected = sampleRate * 60.0 / Double(bpm)
            for i in 1..<points.count {
                let delta = points[i].frame - points[i - 1].frame
                XCTAssertEqual(delta, expected, accuracy: 1e-6, "bpm=\(bpm) 第 \(i) 拍间隔异常")
            }
        }
    }

    // MARK: - 拍号与重音

    func testSixEightGroupingAndAccents() {
        let planner = SchedulePlanner(sampleRate: sampleRate, bpm: 96, timeSignature: .sixEight)
        planner.start(atFrame: 0, countIn: false)
        let points = planner.plan(upTo: sampleRate * 3.7).filter { $0.isMainBeat }

        XCTAssertEqual(points.count, 6, "6/8 一小节应有 6 个主拍")
        XCTAssertEqual(points.map(\.accent), [.strong, .normal, .normal, .group, .normal, .normal])
        XCTAssertEqual(points.map(\.beat), [0, 1, 2, 3, 4, 5])
    }

    func testSimpleMetersHaveOnlyOneAccent() {
        for signature in [TimeSignature.twoFour, .threeFour, .fourFour, .threeEight] {
            let accents = (0..<signature.beatsPerBar).map { signature.accent(atBeat: $0) }
            XCTAssertEqual(accents.filter { $0 == .strong }.count, 1, "\(signature.display) 只应有 1 个强拍")
            XCTAssertFalse(accents.contains(.group), "\(signature.display) 不应有组重音")
        }
    }

    func testAccentDisabledFlattensEverything() {
        let planner = SchedulePlanner(sampleRate: sampleRate,
                                      bpm: 96,
                                      timeSignature: .sixEight,
                                      accentEnabled: false)
        planner.start(atFrame: 0, countIn: false)
        let points = planner.plan(upTo: sampleRate * 5)
        XCTAssertTrue(points.allSatisfy { $0.accent == .normal })
    }

    func testBeatUnitMatchesDenominator() {
        XCTAssertEqual(TimeSignature.fourFour.beatUnit, .quarter)
        XCTAssertEqual(TimeSignature.sixEight.beatUnit, .eighth)
        XCTAssertEqual(TimeSignature.threeEight.beatUnit, .eighth)
        XCTAssertEqual(TimeSignature.sixEight.dottedEquivalentLabel(bpm: 96), "♩. = 32")
        XCTAssertNil(TimeSignature.fourFour.dottedEquivalentLabel(bpm: 96))
    }

    // MARK: - 细分

    func testTripletSubdivisionSpacing() {
        let planner = SchedulePlanner(sampleRate: sampleRate, bpm: 120, timeSignature: .threeFour, subdivision: .three)
        planner.start(atFrame: 0, countIn: false)
        let points = planner.plan(upTo: sampleRate * 0.9)

        let beatFrames = sampleRate * 60.0 / 120.0       // 22050
        let partFrames = beatFrames / 3.0                // 7350

        for (index, point) in points.enumerated() {
            XCTAssertEqual(point.frame, Double(index) * partFrames, accuracy: 1e-6)
            XCTAssertEqual(point.beat, index / 3)
            XCTAssertEqual(point.part, index % 3)
        }
    }

    func testSubdivisionNeverDuplicatesBeat() {
        let planner = SchedulePlanner(sampleRate: sampleRate, bpm: 240, timeSignature: .fourFour, subdivision: .four)
        planner.start(atFrame: 0, countIn: false)
        let points = planner.plan(upTo: sampleRate * 10)
        let frames = points.map(\.frame)
        XCTAssertEqual(Set(frames).count, frames.count, "不应出现重复帧")
        XCTAssertEqual(points.filter { $0.isMainBeat }.count, 40, "10s @240BPM 4/4 应为 10 小节 40 个主拍")
    }

    // MARK: - 变更生效时机

    func testTempoChangeTakesEffectOnNextBeat() {
        let planner = SchedulePlanner(sampleRate: sampleRate, bpm: 120, timeSignature: .fourFour)
        planner.start(atFrame: 0, countIn: false)

        _ = planner.plan(upTo: 1)                   // 只排出第 0 拍（帧 0）
        planner.setBPM(60)
        let points = planner.plan(upTo: 300_000)

        XCTAssertEqual(points[0].frame, 22050, accuracy: 1e-6, "第 1 拍仍按旧速度")
        XCTAssertEqual(points[1].frame, 66150, accuracy: 1e-6, "第 2 拍起按 60BPM，间隔 44100")
        XCTAssertEqual(points[2].frame, 110250, accuracy: 1e-6)
    }

    func testTimeSignatureChangeWaitsForNextBar() {
        let planner = SchedulePlanner(sampleRate: sampleRate, bpm: 120, timeSignature: .fourFour)
        planner.start(atFrame: 0, countIn: false)

        let firstBeat = planner.plan(upTo: 1)
        XCTAssertEqual(firstBeat.first?.beat, 0)
        planner.setTimeSignature(.threeFour)

        let points = planner.plan(upTo: sampleRate * 12).filter { $0.isMainBeat }
        // 当前小节仍是 4 拍，之后每小节 3 拍
        XCTAssertEqual(Array(points.prefix(4)).map(\.beat), [1, 2, 3, 0])
        let after = Array(points.dropFirst(4).prefix(6)).map(\.beat)
        XCTAssertEqual(after, [1, 2, 0, 1, 2, 0], "新拍号应从下一小节首拍开始")
        XCTAssertEqual(points[4].barNumber, 2)
    }

    // MARK: - 预备拍

    func testCountInProducesOneExtraBar() {
        let planner = SchedulePlanner(sampleRate: sampleRate, bpm: 120, timeSignature: .fourFour)
        planner.start(atFrame: 0, countIn: true)
        let points = planner.plan(upTo: sampleRate * 5).filter { $0.isMainBeat }

        XCTAssertEqual(Array(points.prefix(4)).map(\.isCountIn), [true, true, true, true])
        XCTAssertEqual(points[0].barNumber, 0)
        XCTAssertEqual(points[4].isCountIn, false, "第 5 拍进入正式第 1 小节")
        XCTAssertEqual(points[4].barNumber, 1)
        XCTAssertEqual(points[4].beat, 0)
    }

    // MARK: - 停止与复位

    func testStopResetsToBarStart() {
        let planner = SchedulePlanner(sampleRate: sampleRate, bpm: 120, timeSignature: .threeFour)
        planner.start(atFrame: 0, countIn: false)
        _ = planner.plan(upTo: sampleRate * 2)

        planner.stop()
        XCTAssertFalse(planner.isRunning)
        XCTAssertNil(planner.position(at: sampleRate * 2))

        planner.start(atFrame: 1_000_000, countIn: false)
        let points = planner.plan(upTo: 1_100_000)
        XCTAssertEqual(points.first?.beat, 0, "重新开始必须从第一拍起")
        XCTAssertEqual(points.first?.frame, 1_000_000)
        XCTAssertEqual(points.first?.barNumber, 1)
    }

    func testPendingChangesCommitOnStop() {
        let planner = SchedulePlanner(sampleRate: sampleRate, bpm: 120, timeSignature: .fourFour)
        planner.start(atFrame: 0, countIn: false)
        _ = planner.plan(upTo: 1)
        planner.setTimeSignature(.sixEight)
        XCTAssertTrue(planner.hasPendingBarChange)

        planner.stop()
        XCTAssertFalse(planner.hasPendingBarChange)
        XCTAssertEqual(planner.timeSignature, .sixEight, "停止后新拍号应落地，下次开始直接生效")
    }

    // MARK: - 视觉查询

    func testPositionTracksCurrentBeat() {
        let planner = SchedulePlanner(sampleRate: sampleRate, bpm: 120, timeSignature: .fourFour)
        planner.start(atFrame: 0, countIn: false)
        _ = planner.plan(upTo: sampleRate * 5)

        let position = planner.position(at: 22_050 * 2.5)
        XCTAssertEqual(position?.beat, 2)
        XCTAssertEqual(position?.progress ?? 0, 0.5, accuracy: 0.01)
        XCTAssertNil(planner.position(at: -1))
    }

    func testPositionBeforeAnyPointReturnsNil() {
        let planner = SchedulePlanner(sampleRate: sampleRate, bpm: 60, timeSignature: .fourFour)
        planner.start(atFrame: 1000, countIn: false)
        XCTAssertNil(planner.position(at: 500), "开始前不应报告位置")
    }
}
