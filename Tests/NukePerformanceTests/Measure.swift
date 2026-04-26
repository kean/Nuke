// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

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

func measure<T>(
    _ name: String = #function,
    iterations: Int = 5,
    warmup: Int = 1,
    _ body: () async throws -> T
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
