// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// SplitMix64: a few lines of arithmetic, and the same sequence for the same
/// seed in every process and on every platform, which
/// `SystemRandomNumberGenerator` isn't.
///
/// The fixtures are drawn with it, so they come out the same bytes on every
/// run; the network conditions draw with it under `-demoDeterministic 1`,
/// so the same downloads fail every time; and Cache Torture makes the same
/// operations in the same order.
struct DemoRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number from 0 up to 1, from the top 53 bits of the next number.
    ///
    /// `Double.random(in:using:)` takes the bottom bits instead: the fixtures
    /// were drawn with this one, and would come out different bytes.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// A number from 0 up to `bound`, as the remainder of the next number.
    ///
    /// Slightly biased, which a torture doesn't mind, and not what
    /// `Int.random(in:using:)` draws, which would change the operations a run
    /// makes.
    mutating func next(below bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }
}
