/// Deterministic seeded RNG for the whole simulation (GOAL §5).
/// Never use SystemRandomNumberGenerator inside Core — replays and headless
/// tests rely on identical sequences for identical seeds.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform float in [0, 1).
    public mutating func unitFloat() -> Float {
        Float(next() >> 40) * (1.0 / Float(1 << 24))
    }

    /// Uniform float in [lo, hi).
    public mutating func float(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + unitFloat() * (range.upperBound - range.lowerBound)
    }

    /// Uniform integer in the given range.
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
    }
}
