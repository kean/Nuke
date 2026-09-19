// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import os

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
/// **Fixtures.** `DemoPipelineProbe` answers this loader's requests for a
/// fixture URL with ``fixtureLoader``: at the same ``pace``, reported to the
/// same ``hooks``.
final class PacedDataLoader: DataLoading, Sendable {
    /// The fixture loader's pace, so that the fixture loader answering for
    /// this one keeps it. Only a fixture has scans to wait for.
    typealias Pace = DemoFixtureLoader.Pace

    /// When the chunks arrive.
    let pace: Pace
    /// What a screen hears of every load.
    let hooks: DemoLoadHooks
    /// Answers this loader's requests for a fixture URL.
    let fixtureLoader: DemoFixtureLoader

    private let session: URLSession

    init(pace: Pace, hooks: DemoLoadHooks = DemoLoadHooks()) {
        self.pace = pace
        self.hooks = hooks
        self.fixtureLoader = DemoFixtureLoader(pace: pace, hooks: hooks)
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
        let load = PacedLoad(load: DemoLoad(request), pace: pace, hooks: hooks, session: session, didReceiveData: didReceiveData, completion: completion)
        Task {
            await load.start()
        }
        return load
    }
}

/// One load. An actor, so a cancel and the chunks are handled in turn: once
/// `completion` has been called, from either side, nothing else is.
private actor PacedLoad: Cancellable {
    private let load: DemoLoad
    private let pace: PacedDataLoader.Pace
    private let hooks: DemoLoadHooks
    private let session: URLSession
    private let didReceiveData: @Sendable (Data, URLResponse) -> Void
    private let completion: @Sendable (Error?) -> Void
    private var task: Task<Void, Never>?
    private var isFinished = false

    init(
        load: DemoLoad,
        pace: PacedDataLoader.Pace,
        hooks: DemoLoadHooks,
        session: URLSession,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        self.load = load
        self.pace = pace
        self.hooks = hooks
        self.session = session
        self.didReceiveData = didReceiveData
        self.completion = completion
        // Called here, in the pipeline's call to the loader, so a screen
        // hears of the load before anything else happens to it.
        hooks.didStart?(load)
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
            var (data, response) = try await session.data(for: load.request)
            // A cancel that raced the download's end has called `completion`:
            // the hooks hear of nothing after it.
            guard !isFinished else { return }
            response = hooks.willPassResponse?(load, response) ?? response
            if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                throw DataLoader.Error.statusCodeUnacceptable(response.statusCode)
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

// MARK: - Hooks

/// A load of a ``PacedDataLoader`` or a ``DemoFixtureLoader``, as
/// ``DemoLoadHooks`` see it.
struct DemoLoad: Sendable {
    /// Unique among the loads of the app.
    let id: Int
    /// The request the pipeline passed to the loader, with the headers the
    /// pipeline and its delegate added.
    let request: URLRequest

    init(_ request: URLRequest) {
        self.id = Self.lastID.withLock {
            $0 += 1
            return $0
        }
        self.request = request
    }

    private static let lastID = OSAllocatedUnfairLock(initialState: 0)
}

/// What a screen hears from inside the loads of a ``PacedDataLoader``, and of
/// the fixture loader that answers for it: for a screen that shows what went
/// to the server and what came back.
///
/// Each hook is called on the load's own thread, once per load, while the
/// load waits for it, so hand off and return.
struct DemoLoadHooks: Sendable {
    /// The pipeline passed a request to the loader: after `willLoadData`,
    /// before anything went out.
    var didStart: (@Sendable (DemoLoad) -> Void)?
    /// The response, before the pipeline sees it. The pipeline gets the
    /// response this returns, so a screen can take a header out of it and
    /// stand in for a server that doesn't send one.
    var willPassResponse: (@Sendable (DemoLoad, URLResponse) -> URLResponse)?
}
