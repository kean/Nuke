// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
import Nuke

@Suite(.serialized)
@MainActor
struct ImagePrefetcherPerformanceTests {
    /// A grid of 5000 images scrolled a row of four at a time, with the window
    /// the prefetching guide describes: the 24 items past the screen. Every
    /// step starts the row entering the window and stops the one leaving it,
    /// the way `UICollectionViewDataSourcePrefetching` drives the prefetcher,
    /// then lets the pipeline catch up, the way the next frame would. The
    /// downloads never finish, like a network the scroll outruns, so every
    /// step stops the two that are running and starts the next two.
    @Test
    func prefetcherStartStopChurn() async {
        let urls = (0..<5000).map { URL(string: "http://test.com/\($0)")! }
        let rows = stride(from: 0, to: urls.count, by: 4).map { Array(urls[$0..<($0 + 4)]) }
        let windowRowCount = 6
        let maxConcurrentRequestCount = 2

        let dataLoader = StalledDataLoader()
        var configuration = ImagePipeline.Configuration(dataLoader: dataLoader)
        configuration.imageCache = ImageCache()
        // The limiter paces the downloads by the clock, which would time the
        // limiter rather than the prefetcher.
        configuration.isRateLimiterEnabled = false
        let pipeline = ImagePipeline(configuration: configuration)

        // Scrolled from the pipeline's actor rather than the main thread: the
        // wait at the end of every step is then a few hops on the same
        // executor rather than a round trip through the main thread, whose
        // wake-ups would dominate what is measured and vary from run to run.
        await measure { @ImagePipelineActor in
            let prefetcher = ImagePrefetcher(pipeline: pipeline, maxConcurrentRequestCount: maxConcurrentRequestCount)
            var startedCount = dataLoader.startedCount + maxConcurrentRequestCount
            prefetcher.startPrefetching(with: rows[0..<windowRowCount].flatMap { $0 })
            await settle { dataLoader.startedCount >= startedCount }
            for index in windowRowCount..<rows.count {
                prefetcher.startPrefetching(with: rows[index])
                prefetcher.stopPrefetching(with: rows[index - windowRowCount])
                startedCount += maxConcurrentRequestCount
                await settle { dataLoader.startedCount >= startedCount }
            }
            prefetcher.stopPrefetching()
            await settle { dataLoader.cancelledCount >= startedCount }
            // Every step found the downloads it stopped still running.
            #expect(dataLoader.startedCount == startedCount)
            #expect(dataLoader.cancelledCount == startedCount)
        }
    }
}

/// Gives the pipeline hops on its actor until the condition holds: a stopped
/// download hands its slot to the next prefetch, which starts an image task,
/// which starts a download – a hop or more each.
@ImagePipelineActor
private func settle(until condition: () -> Bool) async {
    var hopCount = 0
    while !condition(), hopCount < 1000 {
        await Task { @ImagePipelineActor in }.value
        hopCount += 1
    }
}

/// A network the scroll outruns: it never answers, so every prefetch that
/// starts is still downloading when it is stopped.
private final class StalledDataLoader: DataLoading {
    private let _startedCount = OSAllocatedUnfairLock(initialState: 0)
    private let _cancelledCount = OSAllocatedUnfairLock(initialState: 0)

    /// The number of downloads the pipeline has started, and of the ones it
    /// has cancelled since.
    var startedCount: Int { _startedCount.withLock { $0 } }
    var cancelledCount: Int { _cancelledCount.withLock { $0 } }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        _startedCount.withLock { $0 += 1 }
        return StalledTask(cancelledCount: _cancelledCount)
    }

    private struct StalledTask: Cancellable {
        let cancelledCount: OSAllocatedUnfairLock<Int>

        func cancel() {
            cancelledCount.withLock { $0 += 1 }
        }
    }
}
