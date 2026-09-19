// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: `ImageRequest.Options.disableDiskCacheWrites` is ignored when
// the pipeline stores an *encoded* image (processed image or thumbnail) in the
// disk cache.
//
// Expected: a request with `.disableDiskCacheWrites` never writes to the disk
// cache ("Disables disk cache writes"), and `Delegate.willCache` is not called
// for it ("This method is called only if the request parameters and data
// caching policy of the pipeline already allow caching").
//
// Actual: with `.automatic`, `.storeAll`, or `.storeEncodedImages`, the
// encoded image is written under the processed key and `willCache` is called.
// The original-data path (`TaskFetchOriginalData.shouldStoreDataInDiskCache`)
// does check the option, but `TaskLoadImage.shouldStoreResponseInDataCache`
// (Sources/Nuke/Tasks/TaskLoadImage.swift:199) never looks at
// `request.options`. The check existed in Nuke 10 (`shouldStoreFinalImageInDiskCache`)
// and was dropped in 19423094 "TaskLoadImage no longer needs to check
// subscribed tasks", which removed the subscriber walk without replacing it
// with a `request.options` check (the task key includes the options, so a
// plain check on `request.options` is enough).
@Suite(.timeLimit(.minutes(5)))
struct BugDisableDiskCacheWritesEncodedImagesTests {
    @Test(arguments: [ImagePipeline.DataCachePolicy.automatic, .storeAll, .storeEncodedImages])
    func processedImageIsNotStoredWhenDiskWritesAreDisabled(policy: ImagePipeline.DataCachePolicy) async throws {
        // GIVEN
        let dataCache = MockDataCache()
        let delegate = WillCacheCountingDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
            $0.dataCache = dataCache
            $0.dataCachePolicy = policy
            $0.makeImageEncoder = { _ in MockImageEncoder(result: Test.data) }
        }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")], options: [.disableDiskCacheWrites])

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN nothing is written (actual: "http://test.com/example.jpegp1" is stored)
        #expect(dataCache.store.isEmpty, "Stored keys: \(dataCache.store.keys.sorted())")
        #expect(delegate.willCacheCount == 0)
    }

    @Test func thumbnailIsNotStoredWhenDiskWritesAreDisabled() async throws {
        // GIVEN
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
            $0.dataCache = dataCache
            $0.dataCachePolicy = .automatic
        }
        let request = ImageRequest(url: Test.url, options: [.disableDiskCacheWrites]).with {
            $0.thumbnail = .init(maxPixelSize: 100)
        }

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(dataCache.store.isEmpty, "Stored keys: \(dataCache.store.keys.sorted())")
    }
}

private final class WillCacheCountingDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _willCacheCount = 0
    var willCacheCount: Int { lock.withLock { _willCacheCount } }

    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? {
        lock.withLock { _willCacheCount += 1 }
        return data
    }
}
