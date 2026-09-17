// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CryptoKit
import Foundation
import Nuke
import os

/// The data of the fixtures, made the first time each one is asked for and
/// kept in memory for as long as the app runs.
///
/// A fixture is made once however many loads ask for it at the same time, off
/// the main thread, and its record – size, how long it took, a digest – is
/// kept for the **Fixture Mode** screen. Everything together is a few
/// megabytes, so nothing goes to disk: a fixture that has to be made again is
/// cheaper than a cache to invalidate when the drawing changes.
///
/// Fixtures are made one at a time, on a queue of their own: drawn at the same
/// time as another, a fixture didn't always come out the same bytes (see
/// ``DemoFixtureRenderer``). The biggest takes about a quarter of a second, and
/// the queue keeps the waiting off the threads Swift concurrency runs on.
final class DemoFixtureStore: Sendable {
    static let shared = DemoFixtureStore()

    private let entries = OSAllocatedUnfairLock(initialState: [DemoFixture: Task<Entry, Error>]())
    private let made = OSAllocatedUnfairLock(initialState: [DemoFixture: Record]())

    /// What the store knows about a fixture it made or read.
    struct Record: Sendable {
        let fixture: DemoFixture
        let byteCount: Int
        /// How long drawing and encoding it took, or reading it from the
        /// bundle.
        let duration: Duration
        let isBundled: Bool
        /// The first four bytes of its SHA-256 in hex: the same on every run on
        /// a given system.
        let digest: String
        /// Where each scan starts, for a JPEG; empty for anything else.
        let scanOffsets: [Int]
    }

    struct Entry: Sendable {
        let data: Data
        let record: Record
    }

    /// The data of a fixture, and where its scans start.
    ///
    /// Throws for ``DemoFixture/missing`` the error a server's 404 gets from
    /// `DataLoader`, and for a bundled fixture missing from the bundle.
    func entry(for fixture: DemoFixture) async throws -> Entry {
        let task = entries.withLock { entries in
            if let task = entries[fixture] {
                return task
            }
            let task = Task { [made] in
                let entry = try await withCheckedThrowingContinuation { continuation in
                    Self.queue.async {
                        continuation.resume(with: Result { try Self.make(fixture) })
                    }
                }
                made.withLock { $0[fixture] = entry.record }
                return entry
            }
            entries[fixture] = task
            return task
        }
        return try await task.value
    }

    /// The records of the fixtures made so far.
    var records: [DemoFixture: Record] {
        made.withLock { $0 }
    }

    /// Forgets every fixture, so the next request makes it again. A load in
    /// flight keeps the data it has.
    func removeAll() {
        entries.withLock { $0.removeAll() }
        made.withLock { $0.removeAll() }
    }

    /// Makes every fixture that isn't made yet, and waits for them.
    func makeAll() async {
        await withTaskGroup(of: Void.self) { group in
            for fixture in DemoFixture.all where fixture != .missing {
                group.addTask {
                    _ = try? await self.entry(for: fixture)
                }
            }
        }
    }

    private static func make(_ fixture: DemoFixture) throws -> Entry {
        let start = ContinuousClock.now
        let (data, isBundled) = switch fixture {
        case .webp: (try bundled("fixture-still", "webp"), true)
        case .animatedWebP: (try bundled("fixture-animated", "webp"), true)
        case .video: (try bundled("fixture-video", "mp4"), true)
        case .missing: throw DataLoader.Error.statusCodeUnacceptable(404)
        default: (try DemoFixtureRenderer.data(for: fixture), false)
        }
        let duration = start.duration(to: .now)
        let scanOffsets = fixture.mimeType == "image/jpeg" ? DemoFixtureRenderer.scanOffsets(inJPEG: data) : []
        let digest = SHA256.hash(data: data).prefix(4).map { String(format: "%02x", $0) }.joined()
        let record = Record(fixture: fixture, byteCount: data.count, duration: duration, isBundled: isBundled, digest: digest, scanOffsets: scanOffsets)
        logger.debug("Made \(fixture.name, privacy: .public): \(data.count) bytes in \(duration, privacy: .public), \(digest, privacy: .public)")
        return Entry(data: data, record: record)
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
