// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CryptoKit
import Foundation
import os

/// The data of the fixtures, made the first time each one is asked for and
/// kept in memory for as long as the app runs.
///
/// A fixture is made once however many loads ask for it at the same time, off
/// the main thread, and its size, how long it took, and its digest are logged.
/// Everything together is a few megabytes, so nothing goes to disk: a fixture
/// that has to be made again is cheaper than a cache to invalidate when the
/// drawing changes.
///
/// Fixtures are made one at a time, on a queue of their own: drawn at the same
/// time as another, a fixture didn't always come out the same bytes (see
/// ``DemoFixtureRenderer``). The biggest takes about a quarter of a second, and
/// the queue keeps the waiting off the threads Swift concurrency runs on.
final class DemoFixtureStore: Sendable {
    static let shared = DemoFixtureStore()

    private let entries = OSAllocatedUnfairLock(initialState: [DemoFixture: Task<Entry, Error>]())

    /// The data of a fixture, and the validator a request for the rest of it
    /// is answered against.
    struct Entry: Sendable {
        let data: Data
        /// The first four bytes of the data's SHA-256 in hex: the same on
        /// every run on a given system.
        let digest: String
    }

    /// The data of a fixture.
    ///
    /// Throws for a bundled fixture missing from the bundle.
    func entry(for fixture: DemoFixture) async throws -> Entry {
        let task = entries.withLock { entries in
            if let task = entries[fixture] {
                return task
            }
            let task = Task {
                try await withCheckedThrowingContinuation { continuation in
                    Self.queue.async {
                        continuation.resume(with: Result { try Self.make(fixture) })
                    }
                }
            }
            entries[fixture] = task
            return task
        }
        return try await task.value
    }

    private static func make(_ fixture: DemoFixture) throws -> Entry {
        let start = ContinuousClock.now
        let data = switch fixture {
        case .animatedWebP: try bundled("fixture-animated", "webp")
        case .nukePix: NukePixWriter.badge()
        case .truncatedNukePix: NukePixWriter.truncatedBadge()
        default: try DemoFixtureRenderer.data(for: fixture)
        }
        let duration = start.duration(to: .now)
        let digest = SHA256.hash(data: data).prefix(4).map { String(format: "%02x", $0) }.joined()
        logger.debug("Made \(fixture.name, privacy: .public): \(data.count) bytes in \(duration, privacy: .public), \(digest, privacy: .public)")
        return Entry(data: data, digest: digest)
    }

    private static func bundled(_ name: String, _ ext: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw DemoFixtureError.missingResource("\(name).\(ext)")
        }
        return try Data(contentsOf: url)
    }

    private static let queue = DispatchQueue(label: "com.github.kean.NukeDemo.Fixtures", qos: .userInitiated)

    private static let logger = Logger(subsystem: "com.github.kean.NukeDemo", category: "Fixtures")
}
