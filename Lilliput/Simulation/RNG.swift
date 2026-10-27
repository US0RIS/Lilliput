import Foundation
import CoreGraphics

/// Small, fast, deterministic PRNG. Each construction site owns one, seeded from its
/// window identifier, so a given window always gets the same crew and the same quirks.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform value in [0, 1).
    mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * unit()
    }

    mutating func cg(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        CGFloat(range(Double(lower), Double(upper)))
    }

    mutating func int(_ r: ClosedRange<Int>) -> Int {
        guard r.lowerBound < r.upperBound else { return r.lowerBound }
        let span = UInt64(r.upperBound - r.lowerBound + 1)
        return r.lowerBound + Int(next() % span)
    }

    mutating func chance(_ p: Double) -> Bool {
        unit() < p
    }

    mutating func sign() -> Int {
        chance(0.5) ? 1 : -1
    }

    mutating func pick<T>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        return items[Int(next() % UInt64(items.count))]
    }

    /// Picks an index proportionally to the given non-negative weights.
    mutating func weightedIndex(_ weights: [Double]) -> Int? {
        let total = weights.reduce(0) { $0 + max(0, $1) }
        guard total > 0 else { return nil }
        var roll = unit() * total
        for (i, w) in weights.enumerated() {
            let w = max(0, w)
            if roll < w { return i }
            roll -= w
        }
        return weights.lastIndex(where: { $0 > 0 })
    }
}
