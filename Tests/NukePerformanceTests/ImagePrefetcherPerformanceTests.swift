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
    /// The scroll-away pattern: a fast scroll schedules rows for prefetching
    /// and stops them by URL before most of them get to start.
    @Test
    func startAndStopPrefetchingWithURLs() async {
        let pipeline = makePipeline()
        let urls = (0..<5000).map { URL(string: "http://test.com/\($0)")! }
        let sentinel = [URL(string: "http://test.com/sentinel")!]
        await measure {
            let prefetcher = ImagePrefetcher(pipeline: pipeline, maxConcurrentRequestCount: 8)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // The one request that isn't stopped makes sure the prefetcher
                // runs out of work after the stop. The lock resumes the
                // continuation once, however many times it does on the way.
                let pending = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(initialState: continuation)
                prefetcher.didComplete = {
                    let continuation = pending.withLock { state in
                        defer { state = nil }
                        return state
                    }
                    continuation?.resume()
                }
                prefetcher.startPrefetching(with: urls)
                prefetcher.stopPrefetching(with: urls)
                prefetcher.startPrefetching(with: sentinel)
            }
            withExtendedLifetime(prefetcher) {}
        }
    }

    /// Stops prefetching by URL with nothing outstanding for those URLs: the
    /// rows a scroll leaves after their images have loaded.
    @Test
    func stopPrefetchingWithURLs() async {
        let prefetcher = ImagePrefetcher(pipeline: makePipeline(), maxConcurrentRequestCount: 8)
        let urls = (0..<5000).map { URL(string: "http://test.com/\($0)")! }
        await measure {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // The empty batch reports completion once the prefetcher has
                // processed it, which is after the stop queued before it.
                prefetcher.didComplete = { continuation.resume() }
                prefetcher.stopPrefetching(with: urls)
                prefetcher.startPrefetching(with: [URL]())
            }
        }
    }
}

private func makePipeline() -> ImagePipeline {
    ImagePipeline {
        $0.imageCache = nil
        $0.dataLoader = MockDataLoader()
        $0.isDecompressionEnabled = false
        // The rate limiter is tuned for apps loading over the network, not for
        // a synthetic burst like this one.
        $0.isRateLimiterEnabled = false
        $0.makeImageDecoder = { _ in ImageDecoders.Empty() }
    }
}
