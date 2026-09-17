// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import os

/// A ``DataLoading`` that answers from ``DemoFixture``s, and never touches
/// the network.
///
/// It answers a fixture URL with its fixture, and one of the demo's network
/// URLs with the fixture that stands in for it (see
/// ``DemoFixture/standIn(for:)``). Any other URL fails with
/// ``DemoFixtureError/noFixture(_:)``, and the failure is logged under the
/// `Fixtures` category: offline, a URL the demo doesn't know is a mistake to
/// see, not a request to send.
///
/// `DemoPipelineProbe` hands it every request for a fixture URL, and every
/// request at all while ``DemoFixtureMode`` is offline, so a pipeline keeps
/// its configured loader for the rest. A pipeline can also be configured with
/// one, as Scroll Stress is, to set its ``Pace``.
///
/// **HTTP.** It answers the way a server that supports range requests does,
/// so a download cancelled midway resumes as it would from the photo hosts:
/// an `HTTPURLResponse` with `Content-Length`, an `ETag` made of the
/// fixture's digest, and `Accept-Ranges: bytes`. A request for the rest of a
/// fixture, `Range: bytes=N-`, gets `206 Partial Content` and those bytes,
/// unless its `If-Range` names another `ETag`. Any other `Range` is ignored,
/// as a server may ignore one, and gets the whole fixture.
///
/// **Cancellation.** A cancelled load calls `completion` once, with
/// `URLError(.cancelled)`, and nothing after it – the way `DataLoader` does,
/// because `URLSession` reports a cancelled task as completed. The pipeline
/// frees a data loading slot only when the loader calls `completion`, so a
/// loader that falls silent on cancel, as the documentation of
/// ``DataLoading`` asks and ``ThrottledDataLoader`` does, keeps its slot for
/// good. By the time this `completion` arrives the pipeline has let go of the
/// task, so it reaches nothing of the app's. `completion` follows the cancel
/// within a hop, even while the fixture is still being made.
final class DemoFixtureLoader: DataLoading, Sendable {
    /// How the data arrives.
    let pace: Pace

    private let store: DemoFixtureStore

    init(pace: Pace = .immediate, store: DemoFixtureStore = .shared) {
        self.pace = pace
        self.store = store
    }

    /// When a fixture's bytes arrive, fixed rather than jittered, so a run is
    /// timed like the last one.
    struct Pace: Sendable, Equatable {
        /// The wait before the first byte.
        var latency: Duration = .zero
        /// The most bytes a chunk carries, or `nil` for the whole fixture in
        /// one chunk.
        ///
        /// A progressive JPEG is cut at its scans instead, one chunk each, and
        /// waits ``interval`` for every `chunkSize` bytes in a scan, and at
        /// least ``scanInterval``: each preview the pipeline decodes shows one
        /// more whole scan.
        var chunkSize: Int?
        /// The number of chunks the data comes in whatever its size, in place
        /// of ``chunkSize``, so that every load takes the same time.
        var chunkCount: Int?
        /// The wait before each chunk.
        var interval: Duration = .zero
        /// The least wait before each scan of a progressive JPEG after the
        /// first. The pipeline decodes no preview sooner than
        /// `progressiveDecodingInterval` after the last one, so a scan that
        /// arrives sooner shows up only with the next one.
        var scanInterval: Duration = .zero

        /// Everything at once, right away.
        static let immediate = Pace()

        /// Chunks of `chunkSize` bytes, `interval` apart: the pace of a
        /// ``ThrottledDataLoader`` with the same settings.
        static func throttled(chunkSize: Int, interval: Duration) -> Pace {
            Pace(chunkSize: chunkSize, interval: interval)
        }

        /// `count` chunks, `interval` apart, whatever the size.
        static func chunks(_ count: Int, interval: Duration) -> Pace {
            Pace(chunkCount: count, interval: interval)
        }

        /// The most bytes a chunk of `byteCount` bytes of data carries, or
        /// `nil` for all of them in one.
        func chunkSize(for byteCount: Int) -> Int? {
            if let chunkCount, chunkCount > 0 {
                return max(1, (byteCount + chunkCount - 1) / chunkCount)
            }
            return chunkSize
        }
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        let load = Load(request: request, pace: pace, store: store, didReceiveData: didReceiveData, completion: completion)
        Task {
            await load.start()
        }
        return load
    }
}

/// One load. An actor, so a cancel and the chunks are handled in turn: once
/// `completion` has been called, from either side, nothing else is.
private actor Load: Cancellable {
    private let request: URLRequest
    private let pace: DemoFixtureLoader.Pace
    private let store: DemoFixtureStore
    private let didReceiveData: @Sendable (Data, URLResponse) -> Void
    private let completion: @Sendable (Error?) -> Void
    private var task: Task<Void, Never>?
    private var isFinished = false

    init(
        request: URLRequest,
        pace: DemoFixtureLoader.Pace,
        store: DemoFixtureStore,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        self.request = request
        self.pace = pace
        self.store = store
        self.didReceiveData = didReceiveData
        self.completion = completion
    }

    func start() {
        guard !isFinished else { return } // Cancelled before it started
        task = Task {
            await run()
        }
    }

    nonisolated func cancel() {
        Task {
            await finish(URLError(.cancelled))
        }
    }

    private func run() async {
        let url = request.url
        do {
            guard let fixture = url.flatMap(DemoFixture.standIn(for:)) else {
                Self.logger.error("\(DemoFixtureError.noFixture(url).localizedDescription, privacy: .public)")
                throw DemoFixtureError.noFixture(url)
            }
            // Suspends while the fixture is made, which lets a cancel through.
            let entry = try await store.entry(for: fixture)
            let reply = Reply(to: request, url: url ?? fixture.url, fixture: fixture, entry: entry)
            try await wait(pace.latency)
            for (range, wait) in chunks(of: entry, in: reply.body) {
                try await self.wait(wait)
                guard !isFinished else { return }
                didReceiveData(entry.data[range], reply.response)
            }
            finish(nil)
        } catch {
            finish(error)
        }
    }

    /// The ranges of the data to send, each with the wait before it: the
    /// bytes of `body`, which is all of them unless the request asked for
    /// the rest.
    private func chunks(of entry: DemoFixtureStore.Entry, in body: Range<Int>) -> [(Range<Int>, Duration)] {
        let count = body.count
        guard let chunkSize = pace.chunkSize(for: count), chunkSize > 0, count > 0 else {
            return [(body, .zero)]
        }
        let scans = entry.record.scanOffsets
        if scans.count > 1 {
            // A scan per chunk, the first one with the headers before it. The
            // rest of a fixture starts with the rest of a scan.
            let bounds = [body.lowerBound] + scans.dropFirst().filter { body.lowerBound < $0 && $0 < body.upperBound } + [body.upperBound]
            return zip(bounds, bounds.dropFirst()).enumerated().map { index, bound in
                let (start, end) = bound
                let steps = ((end - start) + chunkSize - 1) / chunkSize
                let wait = pace.interval * max(1, steps)
                return (start..<end, index == 0 ? wait : max(wait, pace.scanInterval))
            }
        }
        return stride(from: body.lowerBound, to: body.upperBound, by: chunkSize).map { start in
            (start..<min(start + chunkSize, body.upperBound), pace.interval)
        }
    }

    private func wait(_ duration: Duration) async throws {
        guard duration > .zero else { return }
        try await Task.sleep(for: duration)
    }

    private func finish(_ error: Error?) {
        guard !isFinished else { return }
        isFinished = true
        task?.cancel()
        completion(error)
    }

    private static let logger = Logger(subsystem: "com.github.kean.NukeDemo", category: "Fixtures")
}

/// What a server that supports range requests answers for a fixture: the
/// status and headers, and which of the fixture's bytes go in the body.
private struct Reply {
    let response: HTTPURLResponse
    let body: Range<Int>

    init(to request: URLRequest, url: URL, fixture: DemoFixture, entry: DemoFixtureStore.Entry) {
        let count = entry.data.count
        // A strong validator: the same bytes on every run give the same one.
        let entityTag = "\"\(entry.record.digest)\""
        var headers = [
            "Content-Type": fixture.mimeType,
            "ETag": entityTag,
            "Accept-Ranges": "bytes"
        ]
        let status: Int
        if let start = Self.rangeStart(of: request), start < count,
           request.value(forHTTPHeaderField: "If-Range").map({ $0 == entityTag }) ?? true {
            status = 206
            body = start..<count
            headers["Content-Range"] = "bytes \(start)-\(count - 1)/\(count)"
        } else {
            status = 200
            body = 0..<count
        }
        headers["Content-Length"] = String(body.count)
        response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    /// `N` of `Range: bytes=N-`, the one kind of range the pipeline asks for.
    private static func rangeStart(of request: URLRequest) -> Int? {
        guard let range = request.value(forHTTPHeaderField: "Range"),
              range.hasPrefix("bytes="), range.hasSuffix("-") else {
            return nil
        }
        return Int(range.dropFirst("bytes=".count).dropLast())
    }
}
