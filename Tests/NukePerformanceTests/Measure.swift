// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

func measure(
    _ name: String = #function,
    iterations: Int = 3,
    _ body: () throws -> Void
) rethrows {
    let clock = ContinuousClock()
    var samples: [Duration] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
        samples.append(try clock.measure(body))
    }
    report(name: name, samples: samples)
}

func measure(
    _ name: String = #function,
    iterations: Int = 3,
    _ body: () async throws -> Void
) async rethrows {
    let clock = ContinuousClock()
    var samples: [Duration] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
        samples.append(try await clock.measure(body))
    }
    report(name: name, samples: samples)
}

private func report(name: String, samples: [Duration]) {
    let ms = samples.map(\.milliseconds)
    let mean = ms.reduce(0, +) / Double(ms.count)
    let stddev = (ms.map { pow($0 - mean, 2) }.reduce(0, +) / Double(ms.count)).squareRoot()
    let list = ms.map(fmt).joined(separator: ", ")
    print("[\(name)] avg=\(fmt(mean))ms stddev=\(fmt(stddev))ms min=\(fmt(ms.min() ?? 0))ms max=\(fmt(ms.max() ?? 0))ms n=\(ms.count) samples=[\(list)]")
}

private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

private extension Duration {
    var milliseconds: Double {
        let (s, a) = components
        return Double(s) * 1_000 + Double(a) / 1_000_000_000_000_000
    }
}
