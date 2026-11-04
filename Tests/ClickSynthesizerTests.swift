import XCTest
@testable import MetronomeCore

final class ClickSynthesizerTests: XCTestCase {
    func testAllThemeSoundsAreBoundedAndHaveSilentEdges() {
        for timbre in Timbre.allCases {
            for sampleRate in [44100.0, 48000.0] {
                for semitones in [0.0, 4, 7] {
                    for countIn in [false, true] {
                        for subdivision in [false, true] {
                            let frequency = timbre.baseFrequency * pow(2, semitones / 48) * (countIn ? 0.86 : 1)
                            let duration = timbre.duration * (subdivision ? 0.72 : 1)
                            let peak: Float = subdivision ? 0.196 : 0.98
                            let samples = ClickSynthesizer.render(timbre: timbre, frequency: frequency, duration: duration, peak: peak, sampleRate: sampleRate)
                            XCTAssertFalse(samples.isEmpty)
                            XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) <= 0.99001 })
                            XCTAssertEqual(samples.first, 0)
                            XCTAssertEqual(samples.last, 0)
                            XCTAssertEqual(samples.map { abs($0) }.max() ?? 0, peak, accuracy: 0.00001)
                            XCTAssertLessThanOrEqual(Double(samples.count) / sampleRate, 60 / 400 / 4)
                        }
                    }
                }
            }
        }
    }

    func testMechanicalClicksHaveFastImpactAndQuietTail() {
        for timbre in Timbre.allCases {
            for sampleRate in [44100.0, 48000.0] {
                let samples = ClickSynthesizer.render(timbre: timbre, frequency: timbre.baseFrequency,
                                                      duration: timbre.duration, peak: 0.8, sampleRate: sampleRate)
                let peakIndex = samples.indices.max { abs(samples[$0]) < abs(samples[$1]) }!
                XCTAssertLessThan(Double(peakIndex) / sampleRate, 0.005, "拍点应在撞击开始后 5ms 内达到峰值")
                let energy = samples.reduce(0.0) { $0 + Double($1 * $1) }
                let tailEnergy = samples.dropFirst(Int(0.020 * sampleRate)).reduce(0.0) { $0 + Double($1 * $1) }
                XCTAssertLessThan(tailEnergy / energy, 0.01, "20ms 后的余音应迅速消退")
            }
        }
    }

    func testThemesProduceDifferentWaveforms() {
        let waveforms = Timbre.allCases.map {
            ClickSynthesizer.render(timbre: $0, frequency: $0.baseFrequency, duration: $0.duration, peak: 0.8, sampleRate: 44100)
        }
        for i in waveforms.indices {
            for j in waveforms.indices where j > i {
                // 比较可听撞击段，避免快速衰减后的近静音尾部稀释材质差异。
                let n = min(Int(0.010 * 44100), min(waveforms[i].count, waveforms[j].count))
                let distance = (0..<n).reduce(0.0) { $0 + Double(abs(waveforms[i][$1] - waveforms[j][$1])) } / Double(n)
                XCTAssertGreaterThan(distance, 0.05)
            }
        }
    }
}
