import Foundation

/// 撞击瞬态与阻尼模态合成，供 SoundBank 预渲染，不参与播放计时。
enum ClickSynthesizer {
    static func render(timbre: Timbre, frequency: Double, duration: Double,
                       peak: Float, sampleRate: Double) -> [Float] {
        let total = Int(duration * sampleRate)
        guard total > 1 else { return [] }
        // 非整数共振模态模拟机身材质，避免持续纯音和电子滑音。
        let modes: [(ratio: Double, gain: Double, damping: Double)]
        switch timbre {
        case .crystalTick:
            modes = [(0.63, 0.24, 1.3), (1, 0.46, 1), (1.91, 0.20, 1.7), (2.69, 0.10, 2.5)]
        case .woodKnock:
            modes = [(0.53, 0.36, 1.1), (1, 0.36, 1), (1.48, 0.20, 1.6), (2.17, 0.08, 2.4)]
        case .feltHammer:
            modes = [(0.55, 0.46, 1.1), (1, 0.36, 1), (1.93, 0.14, 1.9), (2.64, 0.04, 2.8)]
        case .electroPulse:
            modes = [(0.72, 0.22, 1.3), (1, 0.44, 1), (2.33, 0.24, 1.8), (3.15, 0.10, 2.7)]
        }
        var samples = [Float](repeating: 0, count: total)
        let fadeFrames = max(1, Int(0.003 * sampleRate))
        // 两级低通之差形成带限接触噪声，减轻手机扬声器上的尖锐嘶声。
        let fastCoefficient = 1 - exp(-2 * .pi * min(frequency * 2.2, sampleRate * 0.4) / sampleRate)
        let slowCoefficient = 1 - exp(-2 * .pi * frequency * 0.35 / sampleRate)
        var fastNoise = 0.0
        var slowNoise = 0.0
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        var maximum: Float = 0
        for i in 0..<total {
            let t = Double(i) / sampleRate
            var resonance = 0.0
            // 主撞击后跟随微弱的机件接触，间隔很短，听感仍是一个拍点。
            for (delay, strength) in [(0.0, 1.0), (0.0016, 0.18)] {
                let age = t - delay
                guard age >= 0 else { continue }
                let attack = min(age / timbre.attack, 1)
                for mode in modes {
                    resonance += strength * mode.gain * attack
                        * sin(2 * .pi * frequency * mode.ratio * age)
                        * exp(-age * timbre.decay * mode.damping)
                }
            }
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let noise = Double(seed >> 11) / Double(UInt64(1) << 53) * 2 - 1
            fastNoise += fastCoefficient * (noise - fastNoise)
            slowNoise += slowCoefficient * (noise - slowNoise)
            let contact = (fastNoise - slowNoise) * timbre.noiseMix
                * min(t / timbre.attack, 1) * exp(-t * timbre.decay * 2.4)
            let fade = min(Double(total - 1 - i) / Double(fadeFrames), 1)
            let sample = Float(tanh((resonance + contact) * fade))
            samples[i] = sample
            maximum = max(maximum, abs(sample))
        }
        if maximum > 0.0001 {
            let scale = min(max(peak, 0), 0.99) / maximum
            for i in samples.indices { samples[i] *= scale }
        }
        return samples
    }
}
