// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

/// A ``DataLoading`` that downloads a response with `URLSession` and hands it
/// to the pipeline in chunks, a fixed wait apart, so that a download lasts
/// long enough to watch: long enough for other downloads to wait for its
/// slot, or for a person to cancel it halfway.
///
/// The response comes over the network at full speed; it's the pipeline that
/// sees a slow connection. The request goes out as the pipeline made it,
/// headers and all, and a status outside 200..<300 fails the load.
///
/// **Cancellation.** Every load ends with exactly one call to `completion`,
/// a cancelled one included, with `URLError(.cancelled)`, and nothing after
/// it. That's where it differs from ``ThrottledDataLoader``, which follows the
/// documentation of ``DataLoading`` and calls nothing after a cancel. The
/// pipeline frees a download's data loading slot when the loader calls
/// `completion`, and on nothing else, so a loader that falls silent keeps the
/// slot of every download cancelled midway, and the pipeline with it. By the
/// time this `completion` arrives the pipeline has let go of the download, so
/// it reaches nothing of the app's.
///
/// **Offline.** `DemoPipelineProbe` answers the requests of a pipeline
/// configured with this loader with ``fixtureLoader``: the fixtures, at the
/// same ``pace``.
final class PacedDataLoader: DataLoading, Sendable {
    /// The fixture loader's pace, so that the loader standing in for this one
    /// offline keeps it. Only a fixture has scans to wait for.
    typealias Pace = DemoFixtureLoader.Pace

    /// When the chunks arrive.
    let pace: Pace
    /// Answers this loader's requests while the demo is offline.
    let fixtureLoader: DemoFixtureLoader

    private let session: URLSession

    init(pace: Pace) {
        self.pace = pace
        self.fixtureLoader = DemoFixtureLoader(pace: pace)
        // The session a `.withDataCache` configuration gives its own loader:
        // the pipeline's disk cache is the one that caches.
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        let load = PacedLoad(request: request, pace: pace, session: session, didReceiveData: didReceiveData, completion: completion)
        Task {
            await load.start()
        }
        return load
    }
}

/// One load. An actor, so a cancel and the chunks are handled in turn: once
/// `completion` has been called, from either side, nothing else is.
private actor PacedLoad: Cancellable {
    private let request: URLRequest
    private let pace: PacedDataLoader.Pace
    private let session: URLSession
    private let didReceiveData: @Sendable (Data, URLResponse) -> Void
    private let completion: @Sendable (Error?) -> Void
    private var task: Task<Void, Never>?
    private var isFinished = false

    init(
        request: URLRequest,
        pace: PacedDataLoader.Pace,
        session: URLSession,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        self.request = request
        self.pace = pace
        self.session = session
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
        do {
            // Suspends while the response downloads, which lets a cancel
            // through: it cancels the download too.
            let (data, response) = try await session.data(for: request)
            if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                throw URLError(.badServerResponse)
            }
            try await wait(pace.latency)
            let chunkSize = pace.chunkSize(for: data.count) ?? data.count
            for start in stride(from: 0, to: data.count, by: max(1, chunkSize)) {
                try await wait(pace.interval)
                guard !isFinished else { return }
                // The pipeline appends the chunks, so each one carries only
                // new bytes.
                didReceiveData(data.subdata(in: start..<min(start + chunkSize, data.count)), response)
            }
            finish(nil)
        } catch {
            finish(error)
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
}
