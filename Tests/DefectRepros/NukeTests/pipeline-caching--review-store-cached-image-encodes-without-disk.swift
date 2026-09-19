// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG (efficiency): `ImagePipeline.Cache.storeCachedImage(_:for:caches:)`
// encodes the image for the disk layer before it checks whether there is a
// disk layer to write to. When the pipeline has no data cache (the default
// configuration, `ImagePipeline.shared` included), when the delegate returns
// `nil` from `dataCache(for:)`, or when the request has `.disableDiskCacheWrites`,
// the image is still encoded – synchronously, on the calling thread – and the
// result is thrown away by `storeCachedData(_:for:)`.
//
// Expected: with the default `caches: [.all]`, no encoding happens unless the
// data is going to be stored. The pipeline's own path (`TaskLoadImage.storeImageInDataCache`)
// resolves the data cache first and never encodes without one.
//
// Actual: `encodeImage(_:for:)` runs unconditionally inside
// `if caches.contains(.disk), !image.isPreview` (Sources/Nuke/Pipeline/ImagePipeline+Cache.swift:88),
// and the data cache and the write option are checked only afterwards, in
// `storeCachedData` (:176). A full-size JPEG/HEIF encode costs tens of
// milliseconds, and the doc for this method advertises it as safe to call
// from the main thread.
@Suite(.timeLimit(.minutes(5)))
struct BugStoreCachedImageEncodesWithoutDiskTests {
    @Test func imageIsNotEncodedWhenThereIsNoDataCache() {
        // GIVEN the default configuration: memory cache only
        let encoder = MockImageEncoder(result: Test.data)
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = MockImageCache()
            $0.makeImageEncoder = { _ in encoder }
        }
        #expect(pipeline.configuration.dataCache == nil)

        // WHEN
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)

        // THEN (actual: 1)
        #expect(encoder.encodeCount == 0)
    }

    @Test func imageIsNotEncodedWhenTheRequestDisablesDiskWrites() {
        // GIVEN
        let encoder = MockImageEncoder(result: Test.data)
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = MockImageCache()
            $0.dataCache = dataCache
            $0.makeImageEncoder = { _ in encoder }
        }
        let request = ImageRequest(url: Test.url, options: [.disableDiskCacheWrites])

        // WHEN
        pipeline.cache.storeCachedImage(Test.container, for: request)

        // THEN nothing is stored, and nothing should have been encoded (actual: 1)
        #expect(dataCache.store.isEmpty)
        #expect(encoder.encodeCount == 0)
    }
}
