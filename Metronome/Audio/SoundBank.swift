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

        // 电平按「峰值」定义，而不是乘在 tanh 输出上的系数——
        // tanh 会把原始波形压到 0.6 左右，用系数控制响度会让实际电平低到 -11dB。
        var peak: Float
        switch accent {
        case .strong: peak = 0.98
        case .group: peak = 0.88
        case .normal: peak = 0.80
        }

        if countIn {
            // 预备拍：低一个八度、略轻，明确传达「这是准备，不是开始」。
            frequency *= 0.5
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

        let buffer = synthesize(frequency: frequency * jitter,
                                duration: duration,
                                decay: timbre.decay,
                                noiseMix: timbre.noiseMix,
                                // 变体增益最高到 ×1.03，钳一下避免归一化后越过满刻度。
                                peak: min(peak * gainJitter, 0.99))
        cache[key] = buffer
        return buffer
    }

    private func synthesize(frequency: Double,
                            duration: Double,
                            decay: Double,
                            noiseMix: Double,
                            peak: Float) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        guard let channel = buffer.floatChannelData?[0] else { return buffer }

        let total = Int(frameCount)
        let fadeOutFrames = max(1, Int(0.004 * sampleRate))
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        var maxValue: Float = 0

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
            let value = Float(tanh((tone + noise) * envelope))
            channel[i] = value
            if abs(value) > maxValue { maxValue = abs(value) }
        }

        // 峰值归一化：把实际波形缩放到设计电平。
        // 这样三种音色、四个重音层级的响度关系由表格决定，而不是由衰减曲线的偶然峰值决定。
        if maxValue > 0.0001 {
            let scale = peak / maxValue
            for i in 0..<total {
                channel[i] *= scale
            }
        }

        return buffer
    }
}
