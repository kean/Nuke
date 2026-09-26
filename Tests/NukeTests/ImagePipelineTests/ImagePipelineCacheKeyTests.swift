// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// The keys ``ImagePipeline/Cache-swift.struct`` produces for the memory and
/// the disk caches, with and without ``ImagePipeline/Delegate-swift.protocol/cacheKey(for:pipeline:)``.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineCacheKeyTests {
    private let pipeline = ImagePipeline {
        $0.dataLoader = MockDataLoader()
        $0.imageCache = MockImageCache()
        $0.dataCache = MockDataCache()
    }
    private var cache: ImagePipeline.Cache { pipeline.cache }

    // MARK: Data Key Format

    /// The data key names the file in the disk cache: a change to its format
    /// orphans every image that is already on disk.
    @Test(arguments: [
        (ImageRequest(url: Test.url).with { $0.thumbnail = .init(maxPixelSize: 400) },
         "http://test.com/example.jpegcom.github/kean/nuke/thumbnail?maxPixelSize=400.0,options=truetruetruetrue"),
        (ImageRequest(url: Test.url).with { $0.thumbnail = .init(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFit) },
         "http://test.com/example.jpegcom.github/kean/nuke/thumbnail?width=400.0,height=400.0,contentMode=.aspectFit,options=truetruetruetrue"),
        (ImageRequest(url: Test.url, processors: [ImageProcessors.Resize(width: 320, unit: .pixels), ImageProcessors.Circle()]),
         "http://test.com/example.jpegcom.github.kean/nuke/resize?s=(320.0, 9999.0),cm=.aspectFit,crop=false,upscale=falsecom.github.kean/nuke/circle"),
        // A composition adds the identifiers of its processors as is
        (ImageRequest(url: Test.url, processors: [ImageProcessors.Composition([ImageProcessors.Resize(width: 320, unit: .pixels), ImageProcessors.Circle()]), ImageProcessors.Anonymous(id: "1", { $0 })]),
         "http://test.com/example.jpegcom.github.kean/nuke/resize?s=(320.0, 9999.0),cm=.aspectFit,crop=false,upscale=falsecom.github.kean/nuke/circle1"),
        // An empty identifier adds nothing
        (ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "", { $0 }), ImageProcessors.Resize(width: 320, unit: .pixels), ImageProcessors.Anonymous(id: "", { $0 })]),
         "http://test.com/example.jpegcom.github.kean/nuke/resize?s=(320.0, 9999.0),cm=.aspectFit,crop=false,upscale=false"),
        // Without a URL, only the processors are left
        (ImageRequest(url: nil, processors: [ImageProcessors.Resize(width: 320, unit: .pixels)]),
         "com.github.kean/nuke/resize?s=(320.0, 9999.0),cm=.aspectFit,crop=false,upscale=false"),
        (ImageRequest(url: nil), "")
    ])
    func dataKeyFormat(request: ImageRequest, key: String) {
        #expect(cache.makeDataCacheKey(for: request) == key)
    }

    // MARK: Default Keys

    @Test func dataCacheKeyAppendsTheThumbnailBeforeTheProcessors() {
        // GIVEN
        let thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])
            .with { $0.thumbnail = thumbnail }

        // THEN
        #expect(cache.makeDataCacheKey(for: request) == Test.url.absoluteString + thumbnail.identifier + "12")
    }

    @Test func customImageIDReplacesTheURLInBothKeys() {
        // GIVEN two URLs that differ only in a transient query parameter
        let lhs = ImageRequest(url: URL(string: "http://test.com/example.jpeg?token=1"), processors: [MockImageProcessor(id: "p1")])
            .with { $0.imageID = "example" }
        let rhs = ImageRequest(url: URL(string: "http://test.com/example.jpeg?token=2"), processors: [MockImageProcessor(id: "p1")])
            .with { $0.imageID = "example" }

        // THEN
        #expect(cache.makeDataCacheKey(for: lhs) == "examplep1")
        #expect(cache.makeDataCacheKey(for: rhs) == "examplep1")
        #expect(cache.makeImageCacheKey(for: lhs) == cache.makeImageCacheKey(for: rhs))
    }

    @Test func resettingImageIDRestoresTheURLBasedKeys() {
        // GIVEN
        var request = ImageRequest(url: Test.url)
        request.imageID = "custom"
        #expect(cache.makeDataCacheKey(for: request) == "custom")

        // WHEN
        request.imageID = nil

        // THEN
        #expect(request.imageID == Test.url.absoluteString)
        #expect(cache.makeDataCacheKey(for: request) == Test.url.absoluteString)
        #expect(cache.makeImageCacheKey(for: request) == cache.makeImageCacheKey(for: Test.request))
    }

    @Test func closureRequestsAreKeyedByTheirID() {
        // GIVEN
        let data = ImageRequest(id: "photo-1", data: { Test.data })
        let image = ImageRequest(id: "photo-1", image: { Test.container })

        // THEN
        #expect(cache.makeDataCacheKey(for: data) == "photo-1")
        #expect(cache.makeDataCacheKey(for: image) == "photo-1")
        #expect(cache.makeImageCacheKey(for: data) == cache.makeImageCacheKey(for: image))
    }

    /// The ID identifies the image, so a closure request whose ID is the URL
    /// string is interchangeable with the URL request as far as the caches go.
    @Test func closureRequestWithTheURLAsTheIDSharesTheCachedImage() {
        // GIVEN
        let request = ImageRequest(id: Test.url.absoluteString, data: { Test.data })

        // WHEN
        cache[Test.request] = Test.container

        // THEN
        #expect(cache.makeDataCacheKey(for: request) == cache.makeDataCacheKey(for: Test.request))
        #expect(cache[request] != nil)
    }

    @Test func equivalentInitializersProduceTheSameKeys() {
        // GIVEN requests that describe the same image in different ways
        let requests: [ImageRequest] = [
            ImageRequest(url: Test.url),
            ImageRequest(urlRequest: URLRequest(url: Test.url)),
            ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)),
            ImageRequest(stringLiteral: Test.url.absoluteString)
        ]

        // THEN
        for request in requests {
            #expect(cache.makeImageCacheKey(for: request) == cache.makeImageCacheKey(for: Test.request))
            #expect(cache.makeDataCacheKey(for: request) == Test.url.absoluteString)
        }
    }

    @Test(arguments: [
        ImageRequest.Options.disableMemoryCache,
        .disableDiskCache,
        .reloadIgnoringCachedData,
        .returnCacheDataDontLoad,
        .skipDecompression,
        .skipDataLoadingQueue
    ])
    func loadingParametersDoNotAffectTheKeys(options: ImageRequest.Options) {
        // GIVEN a request that differs from the default one in everything but
        // what identifies the image
        let request = ImageRequest(url: Test.url, priority: .veryHigh, options: options)
            .with { $0.userInfo["label"] = "feed" }

        // THEN
        #expect(cache.makeImageCacheKey(for: request) == cache.makeImageCacheKey(for: Test.request))
        #expect(cache.makeDataCacheKey(for: request) == cache.makeDataCacheKey(for: Test.request))
    }

    /// The scale is applied when the image is decoded, so it separates the
    /// memory cache entries, but the stored data is the same.
    @Test func scaleIsPartOfTheMemoryKeyButNotTheDataKey() {
        // GIVEN
        let request = ImageRequest(url: Test.url).with { $0.scale = 3 }

        // THEN
        #expect(cache.makeImageCacheKey(for: request) != cache.makeImageCacheKey(for: Test.request))
        #expect(cache.makeDataCacheKey(for: request) == cache.makeDataCacheKey(for: Test.request))

        // WHEN
        cache[Test.request] = Test.container

        // THEN
        #expect(cache[request] == nil)
    }

    /// The hash of a memory cache key covers only the number of processors, so
    /// requests that differ in the order of their processors alone can share
    /// a hash and have to rely on equality to stay apart.
    @Test func processorOrderIsPartOfBothKeys() {
        // GIVEN
        let lhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "a"), MockImageProcessor(id: "b")])
        let rhs = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "b"), MockImageProcessor(id: "a")])

        // THEN
        #expect(cache.makeImageCacheKey(for: lhs) != cache.makeImageCacheKey(for: rhs))
        #expect(cache.makeDataCacheKey(for: lhs) != cache.makeDataCacheKey(for: rhs))
    }

    @Test func thumbnailSeparatesBothKeys() {
        // GIVEN
        let small = ImageRequest(url: Test.url).with { $0.thumbnail = .init(maxPixelSize: 100) }
        let large = ImageRequest(url: Test.url).with { $0.thumbnail = .init(maxPixelSize: 400) }

        // THEN
        #expect(cache.makeImageCacheKey(for: small) != cache.makeImageCacheKey(for: large))
        #expect(cache.makeImageCacheKey(for: small) != cache.makeImageCacheKey(for: Test.request))
        #expect(cache.makeDataCacheKey(for: small) != cache.makeDataCacheKey(for: large))
    }

    // MARK: Delegate Keys

    @Test func delegateKeyIsUsedVerbatimForBothLayers() {
        // GIVEN a delegate that keys the images by a custom ID
        let pipeline = ImagePipeline(delegate: CustomKeyDelegate()) {
            $0.imageCache = MockImageCache()
        }
        let request = ImageRequest(url: Test.url).with { $0.userInfo[.customKey] = "avatar-1" }

        // THEN
        #expect(pipeline.cache.makeDataCacheKey(for: request) == "avatar-1")
        #expect(pipeline.cache.makeImageCacheKey(for: request) == ImageCacheKey(key: "avatar-1"))
    }

    /// The delegate key replaces the whole default key, so it must account
    /// for the processors, the thumbnail, and the scale itself.
    @Test func delegateKeyReplacesEveryComponentOfTheDefaultKey() {
        // GIVEN
        let pipeline = ImagePipeline(delegate: CustomKeyDelegate()) {
            $0.imageCache = MockImageCache()
        }
        let lhs = ImageRequest(url: Test.url).with { $0.userInfo[.customKey] = "avatar-1" }
        let rhs = ImageRequest(url: URL(string: "http://test.com/other.jpeg"), processors: [MockImageProcessor(id: "p1")]).with {
            $0.userInfo[.customKey] = "avatar-1"
            $0.scale = 3
            $0.thumbnail = .init(maxPixelSize: 100)
        }

        // THEN
        #expect(pipeline.cache.makeImageCacheKey(for: lhs) == pipeline.cache.makeImageCacheKey(for: rhs))
        #expect(pipeline.cache.makeDataCacheKey(for: lhs) == pipeline.cache.makeDataCacheKey(for: rhs))
    }

    @Test func delegateReturningNilFallsBackToTheDefaultKeyForThatRequest() {
        // GIVEN a delegate that customizes only some of the requests
        let pipeline = ImagePipeline(delegate: CustomKeyDelegate()) {
            $0.imageCache = MockImageCache()
        }
        let custom = ImageRequest(url: Test.url).with { $0.userInfo[.customKey] = "avatar-1" }

        // THEN
        #expect(pipeline.cache.makeDataCacheKey(for: Test.request) == Test.url.absoluteString)
        #expect(pipeline.cache.makeImageCacheKey(for: Test.request) == ImageCacheKey(request: Test.request))
        #expect(pipeline.cache.makeImageCacheKey(for: custom) != pipeline.cache.makeImageCacheKey(for: Test.request))
    }

    /// A custom key is not confused with a request whose image ID happens to
    /// be the same string.
    @Test func delegateKeyDoesNotCollideWithTheSameImageID() {
        // GIVEN
        let pipeline = ImagePipeline(delegate: CustomKeyDelegate()) {
            $0.imageCache = MockImageCache()
        }
        let custom = ImageRequest(url: Test.url).with { $0.userInfo[.customKey] = "avatar-1" }
        let plain = ImageRequest(url: Test.url).with { $0.imageID = "avatar-1" }

        // WHEN
        pipeline.cache[custom] = Test.container

        // THEN
        #expect(pipeline.cache.makeImageCacheKey(for: custom) != pipeline.cache.makeImageCacheKey(for: plain))
        #expect(pipeline.cache[plain] == nil)
    }

    // MARK: Diagnostics

    @Test func memoryKeyDigestFollowsTheMemoryKey() {
        // GIVEN
        let options = ImageRequest(url: Test.url, options: [.reloadIgnoringCachedData])
        let scaled = ImageRequest(url: Test.url).with { $0.scale = 3 }
        let processed = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // THEN the requests that share an entry share a digest
        let digest = cache.makeImageCacheKeyDigest(for: Test.request)
        #expect(cache.makeImageCacheKeyDigest(for: options) == digest)
        #expect(cache.makeImageCacheKeyDigest(for: scaled) != digest)
        #expect(cache.makeImageCacheKeyDigest(for: processed) != digest)
    }

    @Test func memoryKeyDigestUsesTheDelegateKey() {
        // GIVEN
        let pipeline = ImagePipeline(delegate: CustomKeyDelegate()) {
            $0.imageCache = MockImageCache()
        }
        let lhs = ImageRequest(url: Test.url).with { $0.userInfo[.customKey] = "avatar-1" }
        let rhs = ImageRequest(url: URL(string: "http://test.com/other.jpeg")).with {
            $0.userInfo[.customKey] = "avatar-1"
            $0.scale = 3
        }

        // THEN
        #expect(pipeline.cache.makeImageCacheKeyDigest(for: lhs) == diagnosticsDigest(of: "avatar-1"))
        #expect(pipeline.cache.makeImageCacheKeyDigest(for: rhs) == diagnosticsDigest(of: "avatar-1"))
    }

    @Test func metricsRecordTheKeyOfACachedPreview() async throws {
        // GIVEN a progressive preview in the memory cache
        let dataCache = MockDataCache()
        dataCache.store[Test.url.absoluteString] = Test.data
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = MockImageCache()
            $0.dataCache = dataCache
            $0.isDiagnosticsEnabled = true
        }
        pipeline.cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // THEN the lookup found the entry, and it says it was a preview
        let metrics = try #require(task.metrics)
        let lookup = try #require(metrics.jobs.first?.stages.first)
        #expect(lookup.kind == .memoryLookup)
        #expect(lookup.result == .hit)
        #expect(lookup.isProgressive == true)
        #expect(lookup.cacheKey == pipeline.cache.makeImageCacheKeyDigest(for: Test.request))
    }

    /// With a delegate key, the memory and the disk entries have the same key,
    /// and the metrics say so.
    @Test func metricsRecordTheDelegateKeyForEveryCacheStage() async throws {
        // GIVEN
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline(delegate: CustomKeyDelegate()) {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = MockImageCache()
            $0.dataCache = dataCache
            $0.isDiagnosticsEnabled = true
        }
        let request = ImageRequest(url: Test.url).with { $0.userInfo[.customKey] = "avatar-1" }

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        let stages = metrics.jobs.flatMap(\.stages)
        let keyed = stages.filter { $0.cacheKey != nil }
        #expect(Set(keyed.map(\.kind)) == [.memoryLookup, .diskLookup, .diskStore, .memoryStore])
        #expect(Set(keyed.compactMap(\.cacheKey)) == [diagnosticsDigest(of: "avatar-1")])
        #expect(dataCache.store.keys.sorted() == ["avatar-1"])
    }
}

// MARK: - Helpers

private extension ImageRequest.UserInfoKey {
    static let customKey: ImageRequest.UserInfoKey = "ImagePipelineCacheKeyTests.customKey"
}

/// Keys the images by the custom key in `userInfo`, if there is one.
private final class CustomKeyDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        request.userInfo[.customKey] as? String
    }
}
