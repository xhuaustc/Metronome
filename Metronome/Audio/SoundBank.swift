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

        // 重音在高音上再抬一个八度的错觉，靠音高而非单纯加音量实现，避免削波。
        var frequency = timbre.baseFrequency * pow(2.0, Double(accent.semitoneOffset) / 12.0)
        var amplitude: Float = accent == .normal ? 0.62 : 0.78

        if countIn {
            // 预备拍：低一个八度、略轻，明确传达「这是准备，不是开始」。
            frequency *= 0.5
            amplitude *= 0.66
        }

        if isSubdivision {
            // 细分固定 -14dB，且时值更短，保证不抢主拍。
            amplitude *= 0.2
        }

        // 每个变体做极小的随机化，消除连续数十拍后的机械重复感。
        let jitter = [1.0, 1.004, 1.008][key.variant]
        let gainJitter: Float = [1.0, 0.97, 1.03][key.variant]
        let duration = isSubdivision ? timbre.duration * 0.72 : timbre.duration

        let buffer = synthesize(frequency: frequency * jitter,
                                duration: duration,
                                decay: timbre.decay,
                                noiseMix: timbre.noiseMix,
                                amplitude: amplitude * gainJitter)
        cache[key] = buffer
        return buffer
    }

    private func synthesize(frequency: Double,
                            duration: Double,
                            decay: Double,
                            noiseMix: Double,
                            amplitude: Float) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        guard let channel = buffer.floatChannelData?[0] else { return buffer }

        let total = Int(frameCount)
        let fadeOutFrames = max(1, Int(0.004 * sampleRate))
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15

        for i in 0..<total {
            let t = Double(i) / sampleRate

            // 2ms 起振，避免咔嗒声；之后指数衰减。
            let attack = min(t / 0.002, 1.0)
            var envelope = attack * exp(-t * decay)

            let tail = total - i
            if tail < fadeOutFrames {
                envelope *= Double(tail) / Double(fadeOutFrames)
            }

            // 基频 + 少量二次谐波，给「木质」一点厚度。
            let tone = sin(2 * .pi * frequency * t) * 0.62
                     + sin(2 * .pi * frequency * 2 * t) * 0.14

            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let unit = Double(seed >> 11) / Double(UInt64(1) << 53)
            let noise = (unit * 2 - 1) * noiseMix * exp(-t * decay * 2.4)

            // tanh 软限幅：任何组合下都不会削波。
            let value = tanh((tone + noise) * envelope) * Double(amplitude)
            channel[i] = Float(value)
        }

        return buffer
    }
}
