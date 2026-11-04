import XCTest
@testable import MetronomeCore

final class PendulumTests: XCTestCase {
    func testMainBeatsAlternateSidesAtEveryTempoAndSubdivision() throws {
        for bpm in [30, 96, 240] {
            for subdivision in Subdivision.allCases {
                let planner = SchedulePlanner(sampleRate: 44100, bpm: bpm, timeSignature: .threeFour, subdivision: subdivision)
                planner.start(atFrame: 0, countIn: true)
                let interval = 44100 * 60 / Double(bpm)
                for beat in 0..<8 {
                    _ = planner.plan(upTo: Double(beat + 2) * interval)
                    let angle = try XCTUnwrap(planner.position(at: Double(beat) * interval)).pendulumAngle()
                    XCTAssertEqual(angle, beat.isMultiple(of: 2) ? -18 : 18, accuracy: 0.00001)
                    let middle = try XCTUnwrap(planner.position(at: (Double(beat) + 0.5) * interval)).pendulumAngle()
                    XCTAssertEqual(middle, 0, accuracy: 0.00001)
                }
                planner.stop()
                XCTAssertNil(planner.position(at: interval))
                planner.start(atFrame: 0, countIn: false)
                _ = planner.plan(upTo: interval)
                XCTAssertEqual(try XCTUnwrap(planner.position(at: 0)).pendulumAngle(), -18, accuracy: 0.00001)
            }
        }
    }

    func testLookaheadChangesDoNotMoveAlreadyScheduledPendulum() throws {
        let planner = SchedulePlanner(sampleRate: 44100, bpm: 120, timeSignature: .threeFour, subdivision: .four)
        planner.start(atFrame: 0, countIn: true)
        _ = planner.plan(upTo: 44100)
        let before = try XCTUnwrap(planner.position(at: 11025)).pendulumAngle()
        planner.setBPM(60)
        planner.setSubdivision(.none)
        planner.setTimeSignature(.sixEight)
        _ = planner.plan(upTo: 5 * 44100)
        XCTAssertEqual(try XCTUnwrap(planner.position(at: 11025)).pendulumAngle(), before, accuracy: 0.00001)
        let interval = 44100 * 60 / 60.0
        let points = planner.plan(upTo: 10 * 44100).filter(\.isMainBeat)
        for (left, right) in zip(points, points.dropFirst()) {
            let leftAngle = try XCTUnwrap(planner.position(at: left.frame)).pendulumAngle()
            let rightAngle = try XCTUnwrap(planner.position(at: right.frame)).pendulumAngle()
            XCTAssertEqual(leftAngle, -rightAngle, accuracy: 0.00001)
            XCTAssertEqual(right.frame - left.frame, interval, accuracy: 0.00001)
            XCTAssertEqual(try XCTUnwrap(planner.position(at: (left.frame + right.frame) / 2)).pendulumAngle(), 0, accuracy: 0.00001)
        }
    }

    func testPruningHistoryPreservesSwingDirection() throws {
        let planner = SchedulePlanner(sampleRate: 44100, bpm: 240, timeSignature: .threeEight, subdivision: .four)
        planner.start(atFrame: 0, countIn: false)
        for beat in 0..<200 {
            let frame = Double(beat) * 11025
            _ = planner.plan(upTo: frame + 11026)
            XCTAssertEqual(try XCTUnwrap(planner.position(at: frame)).pendulumAngle(), beat.isMultiple(of: 2) ? -18 : 18, accuracy: 0.00001)
        }
    }
}
