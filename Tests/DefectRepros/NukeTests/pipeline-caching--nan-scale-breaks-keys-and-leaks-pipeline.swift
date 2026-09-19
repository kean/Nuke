// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: a request whose `scale` is NaN produces keys that aren't
// equal to themselves, which breaks the `Hashable` contract of
// `MemoryCacheKey` and `TaskFetchOriginalImageKey`.
//
// Expected: a request can always read back what was stored for it, and a
// pipeline with no outstanding work is deallocated once the app drops it.
//
// Actual:
// - `pipeline.cache[request] = image` followed by `pipeline.cache[request]`
//   returns `nil`, and each load adds another entry to the memory cache that
//   can never be read or removed (only evicted).
// - The `TaskFetchOriginalImage` is never removed from its task pool:
//   `TaskPool.publisherForKey` removes it with `map[key] = nil` on disposal, and
//   `TaskFetchOriginalImageKey` is a struct whose synthesized `==` compares
//   `scale` (Sources/Nuke/Internal/ImageRequestKeys.swift:93), so the lookup
//   fails. The leaked task holds the pipeline strongly, so the pipeline and
//   everything it owns (caches, data loader) leak for good. (`TaskLoadImageKey`
//   is a class with an `===` short-circuit, so its pool doesn't leak.)
//
// NaN is invalid input, but it's a `CGFloat` that is easy to produce (e.g.
// dividing by a zero-sized bounds), and nothing rejects or normalizes it.
@Suite(.timeLimit(.minutes(5)))
struct BugNaNScaleKeysTests {
    @Test func imageStoredForNaNScaleCanBeReadBack() {
        // GIVEN
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = MockImageCache()
        }
        let request = ImageRequest(url: Test.url).with { $0.scale = .nan }

        // WHEN
        pipeline.cache[request] = Test.container

        // THEN (actual: nil)
        #expect(pipeline.cache[request] != nil)
    }

    @Test(arguments: [CGFloat(1), .nan])
    func pipelineIsDeallocatedAfterLoading(scale: CGFloat) async throws {
        // GIVEN
        let weakPipeline = WeakRef<ImagePipeline>()
        do {
            let pipeline = ImagePipeline {
                $0.dataLoader = MockDataLoader()
                $0.imageCache = nil
            }
            weakPipeline.value = pipeline
            let request = ImageRequest(url: Test.url).with { $0.scale = scale }

            // WHEN
            _ = try await pipeline.image(for: request)
        }

        // THEN nothing holds the pipeline once its work is done (passes for 1
        // within milliseconds, never happens for NaN)
        await waitUntil(timeout: .seconds(5)) { weakPipeline.value == nil }
        #expect(weakPipeline.value == nil)
    }
}
