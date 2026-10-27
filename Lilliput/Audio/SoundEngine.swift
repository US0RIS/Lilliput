import Foundation
import AppKit

enum SoundKind: CaseIterable {
    case tap
    case clunk
    case ratchet
    case pop
}

/// Quiet, synthesized construction sounds. Generated in memory at first use; no audio
/// files ship with the app. Off unless the user enables it.
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    var enabled = false
    var volume: Float = 0.12

    private var pools: [SoundKind: [NSSound]] = [:]
    private var lastPlay: [SoundKind: TimeInterval] = [:]
    private var recentPlays: [TimeInterval] = []

    func play(_ kind: SoundKind) {
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlay[kind], now - last < 0.09 { return }
        recentPlays.removeAll { now - $0 > 1 }
        guard recentPlays.count < 6 else { return }
        lastPlay[kind] = now
        recentPlays.append(now)

        if pools[kind] == nil {
            let data = Self.wav(for: kind)
            pools[kind] = (0..<3).compactMap { _ in NSSound(data: data) }
        }
        guard let pool = pools[kind], let sound = pool.first(where: { !$0.isPlaying }) else { return }
        sound.volume = volume * Float.random(in: 0.8...1.0)
        sound.play()
    }

    private static func wav(for kind: SoundKind) -> Data {
        let rate = 22_050
        var samples: [Float] = []
        var seed: UInt32 = 0x1234_5678
        func noise() -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(Int32(bitPattern: seed)) / Float(Int32.max)
        }
        func tone(duration: Double, freq: Double, decay: Double, noiseMix: Float, freqEnd: Double? = nil) {
            let n = Int(duration * Double(rate))
            for i in 0..<n {
                let t = Double(i) / Double(rate)
                let f = freqEnd.map { freq + ($0 - freq) * t / duration } ?? freq
                let env = Float(exp(-t * decay))
                let s = Float(sin(2 * .pi * f * t)) * (1 - noiseMix) + noise() * noiseMix
                samples.append(s * env * 0.6)
            }
        }
        switch kind {
        case .tap:
            tone(duration: 0.06, freq: 1900, decay: 85, noiseMix: 0.45)
        case .clunk:
            tone(duration: 0.1, freq: 380, decay: 42, noiseMix: 0.25)
        case .ratchet:
            for _ in 0..<3 {
                tone(duration: 0.025, freq: 2600, decay: 160, noiseMix: 0.6)
                samples.append(contentsOf: [Float](repeating: 0, count: rate / 60))
            }
        case .pop:
            tone(duration: 0.07, freq: 520, decay: 50, noiseMix: 0.1, freqEnd: 900)
        }

        var data = Data()
        func append<T: FixedWidthInteger>(_ v: T) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        let byteCount = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(rate))
        append(UInt32(rate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(byteCount))
        for s in samples {
            append(Int16(max(-1, min(1, s)) * 32_000))
        }
        return data
    }
}
