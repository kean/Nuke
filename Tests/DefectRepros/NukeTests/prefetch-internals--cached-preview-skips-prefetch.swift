// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: a progressive preview in the memory cache makes the prefetcher
// skip the image.
//
// Sources/Nuke/Prefetching/ImagePrefetcher.swift:139
//
//     guard pipeline.cache[request] == nil else { return }
//
// The check treats any memory cache entry as "already prefetched", including a
// preview (`ImageContainer.isPreview == true`). The memory cache holds
// previews by default (`isStoringPreviewsInMemoryCache` is `true`), e.g. the
// progressive scans of a load that was cancelled when its cell scrolled off
// screen. The pipeline itself doesn't treat a cached preview as the image:
// `TaskLoadImage.start()` delivers it as a preview and goes on to load the
// final image (Sources/Nuke/Tasks/TaskLoadImage.swift:14-19).
//
// So the prefetcher does nothing, reports `didComplete` right away as if the
// image were ready, and when the image is displayed later the pipeline still
// has to download it – the delay the prefetcher exists to eliminate
// ("Prefetches and caches images to eliminate delays when requesting the same
// images later").
//
// Expected: the prefetch runs; the final image replaces the preview.
// Actual:   no task is started; the memory cache still holds the preview.
@Suite(.timeLimit(.minutes(5)))
struct ImagePrefetcherCachedPreviewBugRepro {
    @Test func cachedPreviewDoesNotCountAsPrefetched() async {
        // GIVEN a preview left in the memory cache by an earlier load
        let dataLoader = MockDataLoader()
        let observer = ImagePipelineObserver()
        let pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
        }
        pipeline.cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)
        #expect(pipeline.cache[Test.request]?.isPreview == true)
        let prefetcher = ImagePrefetcher(pipeline: pipeline)

        // WHEN
        let done = TestExpectation()
        prefetcher.didComplete = { done.fulfill() }
        prefetcher.startPrefetching(with: [Test.url])
        await done.wait()

        // THEN the final image is prefetched
        #expect(observer.startedTaskCount == 1)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(pipeline.cache[Test.request]?.isPreview == false)
    }
}
