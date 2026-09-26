// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

// The suites in this target must run one at a time: a benchmark that shares
// the machine with another one measures both. `.serialized` only orders the
// tests within a suite, so the NukePerformanceTests scheme turns parallel
// execution off for the whole target ("Execute in parallel" unchecked,
// `parallelizable = "NO"` on its testable). Swift Testing honors it without
// `-parallel-testing-enabled NO`; keep it off in any scheme or test plan that
// runs these suites. In parallel, `asyncAwaitPerformance` samples ranged from
// 69 ms to 967 ms in one run; run serially, they stay within a few percent.

func measure<T>(
    _ name: String = #function,
    iterations: Int = 5,
    warmup: Int = 1,
    _ body: () throws -> T
) rethrows {
    let clock = ContinuousClock()
    try runSamples(name: name, iterations: iterations, warmup: warmup) {
        var result: T?
        let duration = try clock.measure { result = try body() }
        blackHole(result)
        return duration
    }
}

/// Measures `body` with a fresh input from `setup` for every sample.
///
/// `setup` runs before each sample, the warmup included, and isn't timed: use
/// it for an input that a cache would otherwise remember from one sample to
/// the next.
func measure<Input, T>(
    _ name: String = #function,
    iterations: Int = 5,
    warmup: Int = 1,
    setup: () throws -> Input,
    _ body: (Input) throws -> T
) rethrows {
    let clock = ContinuousClock()
    try runSamples(name: name, iterations: iterations, warmup: warmup) {
        let input = try setup()
        var result: T?
        let duration = try clock.measure { result = try body(input) }
        blackHole(result)
        return duration
    }
}

func measure<T>(
    _ name: String = #function,
    iterations: Int = 5,
    warmup: Int = 1,
    _ body: @Sendable () async throws -> T
) async rethrows {
    let clock = ContinuousClock()
    try await runSamples(name: name, iterations: iterations, warmup: warmup) {
        var result: T?
        let duration = try await clock.measure { result = try await body() }
        blackHole(result)
        return duration
    }
}

private func runSamples(
    name: String,
    iterations: Int,
    warmup: Int,
    sample: () throws -> Duration
) rethrows {
    for _ in 0..<warmup { _ = try sample() }
    var samples: [Duration] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
        samples.append(try sample())
    }
    report(name: name, samples: samples)
}

private func runSamples(
    name: String,
    iterations: Int,
    warmup: Int,
    sample: () async throws -> Duration
) async rethrows {
    for _ in 0..<warmup { _ = try await sample() }
    var samples: [Duration] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
        samples.append(try await sample())
    }
    report(name: name, samples: samples)
}

@inline(never)
private func blackHole<T>(_ value: T) {
    withExtendedLifetime(value) {}
}

private func report(name: String, samples: [Duration]) {
    let ms = samples.map(\.milliseconds).sorted()
    let mean = ms.reduce(0, +) / Double(ms.count)
    let stddev = ms.count > 1
        ? (ms.map { pow($0 - mean, 2) }.reduce(0, +) / Double(ms.count - 1)).squareRoot()
        : 0
    let rel = mean > 0 ? stddev / mean * 100 : 0
    let list = ms.map(fmt).joined(separator: ", ")
    print("◇ Measured \(name) avg=\(fmt(mean))ms ±\(String(format: "%.1f", rel))% samples=[\(list)]")
}

private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

private extension Duration {
    var milliseconds: Double {
        let (s, a) = components
        return Double(s) * 1_000 + Double(a) / 1e15
    }
}
