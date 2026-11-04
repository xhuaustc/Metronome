import AVFoundation

/// 预渲染所有音色变体。播放时只做 buffer 调度，不在音频线程里做合成。
final class SoundBank {

    private struct Key: Hashable {
        let timbre: Timbre
        let level: AccentLevel
        let countIn: Bool
        let subdivision: Bool
        let variant: Int
    }

    static let variantsPerLevel = 3

    private let format: AVAudioFormat
    private let sampleRate: Double
    private var cache: [Key: AVAudioPCMBuffer] = [:]

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    func buffer(timbre: Timbre,
                accent: AccentLevel,
                countIn: Bool,
                isSubdivision: Bool,
                variant: Int) -> AVAudioPCMBuffer {
        let key = Key(timbre: timbre,
                      level: accent,
                      countIn: countIn,
                      subdivision: isSubdivision,
                      variant: variant % Self.variantsPerLevel)
        if let cached = cache[key] { return cached }

        // 重音主要靠撞击力度区分，共振频率只轻微抬高，保留同一机械装置的听感。
        var frequency = timbre.baseFrequency * pow(2.0, Double(accent.semitoneOffset) / 48.0)

        // 电平按「峰值」定义，而不是乘在 tanh 输出上的系数——
        // tanh 会把原始波形压到 0.6 左右，用系数控制响度会让实际电平低到 -11dB。
        var peak: Float
        switch accent {
        case .strong: peak = 0.98
        case .group: peak = 0.88
        case .normal: peak = 0.80
        }

        if countIn {
            // 预备拍：略低、略轻，与正式拍点区分。
            frequency *= 0.86
            peak *= 0.62
        }

        if isSubdivision {
            // 细分固定约 -14dB，且时值更短，保证不抢主拍。
            peak *= 0.2
        }

        // 每个变体做极小的随机化，消除连续数十拍后的机械重复感。
        let jitter = [1.0, 1.004, 1.008][key.variant]
        let gainJitter: Float = [1.0, 0.97, 1.03][key.variant]
        let duration = isSubdivision ? timbre.duration * 0.72 : timbre.duration

        let samples = ClickSynthesizer.render(timbre: timbre, frequency: frequency * jitter,
                                              duration: duration, peak: min(peak * gainJitter, 0.99),
                                              sampleRate: sampleRate)
        let frameCount = AVAudioFrameCount(samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        if let channel = buffer.floatChannelData?[0] {
            for i in samples.indices { channel[i] = samples[i] }
        }
        cache[key] = buffer
        return buffer
    }
}
