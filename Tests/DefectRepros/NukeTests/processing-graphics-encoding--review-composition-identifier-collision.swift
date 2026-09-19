// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG (low): `ImageProcessors.Composition.identifier` joins the identifiers of
// its processors with no separator. Two different lists of processors can
// therefore share an identifier, and with it a disk cache key.
// `makeDataCacheKey(for:)` is `imageID + thumbnail id + Composition(processors).identifier`,
// also with no separators.
//
// `[Anonymous(id: "blur"), Anonymous(id: "red")]` and `[Anonymous(id: "blurred")]`
// both give "blurred". Each processor's identifier is unique, which is all
// `ImageProcessing.identifier` asks for ("Returns a string that uniquely
// identifies the processor"). The memory cache keeps them apart, because it
// compares `hashableIdentifier`s element by element. The disk cache doesn't: a
// request with one list is served the processed image the other list stored,
// but only once the memory cache no longer has it. Reverse-DNS identifiers,
// which the docs recommend and the built-in processors use, make a collision
// unlikely. Short `Anonymous` ids, the ones the README uses, don't.
//
// Expected: different processor lists produce different data cache keys, as
// they produce different memory cache keys.
// Actual: "http://test.com/example.jpegblurred" for both.
//
// Sources/Nuke/Processing/ImageProcessors+Composition.swift:48 and
// Sources/Nuke/Pipeline/ImagePipeline+Cache.swift:235
@Suite(.timeLimit(.minutes(5)))
struct CompositionIdentifierCollisionBugRepro {
    @Test func differentProcessorListsHaveDifferentDataCacheKeys() {
        // GIVEN two requests whose processors produce different images
        let pipeline = ImagePipeline { $0.dataLoader = MockDataLoader() }
        let lhs = ImageRequest(url: Test.url, processors: [
            ImageProcessors.Anonymous(id: "blur") { $0 },
            ImageProcessors.Anonymous(id: "red") { $0 }
        ])
        let rhs = ImageRequest(url: Test.url, processors: [
            ImageProcessors.Anonymous(id: "blurred") { $0 }
        ])

        // THEN the memory cache keeps them apart...
        #expect(pipeline.cache.makeImageCacheKey(for: lhs) != pipeline.cache.makeImageCacheKey(for: rhs))

        // ...and so should the disk cache
        #expect(pipeline.cache.makeDataCacheKey(for: lhs) != pipeline.cache.makeDataCacheKey(for: rhs)) // Actual: equal
    }

    @Test func servesTheImageOfAnotherProcessorListFromTheDiskCache() async throws {
        // GIVEN a pipeline that stores processed images in the disk cache only
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.dataCachePolicy = .storeEncodedImages
        }
        let small = ImageRequest(url: Test.url, processors: [
            ImageProcessors.Anonymous(id: "blur") { $0 },
            ImageProcessors.Resize(size: CGSize(width: 10, height: 10), unit: .pixels)
        ])
        // An identifier that happens to equal the concatenation above
        let identity = ImageRequest(url: Test.url, processors: [
            ImageProcessors.Anonymous(id: "blur" + ImageProcessors.Resize(size: CGSize(width: 10, height: 10), unit: .pixels).identifier) { $0 }
        ])

        // WHEN the first request stores a 13x10 image
        _ = try await pipeline.image(for: small)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN the second request, which doesn't resize at all, is served it
        let response = try await pipeline.imageTask(with: identity).response
        #expect(response.cacheType == nil) // Actual: .disk
        #expect(response.image.sizeInPixels == CGSize(width: 640, height: 480)) // Actual: 13x10
    }
}
