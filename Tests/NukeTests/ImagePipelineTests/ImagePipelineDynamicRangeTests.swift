// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import ImageIO

@testable import Nuke

#if canImport(UIKit)
import UIKit
#endif

// The fixtures are generated: a ramp from 0 to 1 next to a patch at 4× SDR white.
// `hdr-pq` has no SDR base image, and `hdr-gainmap` decodes to one by default.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDynamicRangeTests {
    private let dataLoader = MockDataLoader()
    private let dataCache = MockDataCache()
    private let imageCache = MockImageCache()
    private let pq = Test.data(name: "hdr-pq", extension: "heic")
    private let gainMap = Test.data(name: "hdr-gainmap", extension: "jpeg")

    private func makePipeline(_ configure: (inout ImagePipeline.Configuration) -> Void = { _ in }) -> ImagePipeline {
        ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
            configure(&$0)
        }
    }

    private func makeRequest(
        _ data: Data,
        dynamicRange: ImageRequest.DynamicRange = .high,
        processors: [any ImageProcessing] = [],
        thumbnail: ImageRequest.ThumbnailOptions? = nil
    ) -> ImageRequest {
        dataLoader.results[Test.url] = .success((data, URLResponse(url: Test.url, mimeType: nil, expectedContentLength: data.count, textEncodingName: nil)))
        var request = ImageRequest(url: Test.url, processors: processors)
        request.dynamicRange = dynamicRange
        request.thumbnail = thumbnail
        return request
    }

    // MARK: - Decoding

    @Test func requestDefaultsToStandard() {
        #expect(ImageRequest(url: Test.url).dynamicRange == .standard)
    }

    @Test func imageWithNoBaseKeepsItsRange() async throws {
        let image = try await makePipeline().image(for: makeRequest(pq))

        #expect(image.cgImage?.bitsPerComponent ?? 0 > 8)
        #expect(try Self.brightest(in: image) > 3)
#if os(iOS) || os(visionOS)
        #expect(image.isHighDynamicRange)
#endif
    }

    @Test func gainMapIsApplied() async throws {
        let image = try await makePipeline().image(for: makeRequest(gainMap))

#if targetEnvironment(simulator)
        // A simulator can't apply it. What matters is that the image isn't black,
        // which is what a simulator returns for `kCGImageSourceDecodeToHDR`.
        #expect(image.cgImage?.bitsPerComponent == 8)
        #expect(try (0.5...1.2).contains(Self.brightest(in: image)))
#else
        #expect(image.cgImage?.bitsPerComponent ?? 0 > 8)
        #expect(try Self.brightest(in: image) > 3)
#endif
#if os(iOS) && !targetEnvironment(simulator)
        #expect(image.isHighDynamicRange)
#endif
    }

#if canImport(UIKit)
    // `NSImage` applies a gain map on its own when asked for a `CGImage`, so
    // the same can't be said about macOS.
    @Test func gainMapIsIgnoredByDefault() async throws {
        let image = try await makePipeline().image(for: makeRequest(gainMap, dynamicRange: .standard))

        #expect(image.cgImage?.bitsPerComponent == 8)
        #expect(try Self.brightest(in: image) < 1.2)
        #expect(!image.isHighDynamicRange)
    }
#endif

    @Test func orientationIsApplied() async throws {
        let data = Test.data(name: "hdr-gainmap-rotated", extension: "heic")
        let image = try await makePipeline().image(for: makeRequest(data))

#if os(macOS)
        #expect(image.size == CGSize(width: 32, height: 64))
        #expect(image.cgImage?.width == 32)
#else
        #expect(image.imageOrientation == .right)
        #expect(image.cgImage?.width == 64)
#endif
#if !targetEnvironment(simulator)
        #expect(image.cgImage?.bitsPerComponent ?? 0 > 8)
        #expect(try Self.brightest(in: image) > 3)
#endif
    }

    @Test func standardImageDecodesTheSame() async throws {
        let image = try await makePipeline().image(for: makeRequest(Test.data))

        #expect(image.cgImage?.bitsPerComponent == 8)
        #expect(image.cgImage?.width == 640)
        #expect(try (0.5...1.1).contains(Self.brightest(in: image)))
    }

    @Test func scaleIsApplied() async throws {
        var request = makeRequest(pq)
        request.scale = 2
        let image = try await makePipeline().image(for: request)

#if canImport(UIKit)
        #expect(image.scale == 2)
#endif
        #expect(image.cgImage?.width == 64)
    }

    @Test func animationIsKept() async throws {
        let response = try await makePipeline().imageTask(with: makeRequest(Test.data(name: "cat", extension: "gif"))).response

        #expect(response.container.type == .gif)
        #expect(response.container.data != nil)
        #expect(response.container.animation != nil)
    }

    @Test func dataImageIOCantReadFailsAsUsual() async {
        await #expect(throws: ImagePipeline.Error.self) {
            try await makePipeline().image(for: makeRequest(Data([1, 2, 3])))
        }
    }

    // MARK: - Decompression

    // Both ways to decompress an image would lose the HDR: `preparingForDisplay()`
    // goes back to the SDR base of a gain map, and the other draws in 8 bits.
    @Test(arguments: [false, true]) func decompressionIsSkipped(isUsingPrepareForDisplay: Bool) async throws {
        let observer = DecompressionObserver()
        let pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDecompressionEnabled = true
            $0.isUsingPrepareForDisplay = isUsingPrepareForDisplay
        }
        let image = try await pipeline.image(for: makeRequest(pq))

        #expect(observer.decompressionCount == 0)
        #expect(image.cgImage?.bitsPerComponent ?? 0 > 8)

        _ = try await pipeline.image(for: makeRequest(pq, dynamicRange: .standard))

        #expect(observer.decompressionCount == 1)
    }

    // MARK: - Thumbnails

    @Test func thumbnailIsDecodedToHighDynamicRange() async throws {
        let request = makeRequest(pq, thumbnail: .init(maxPixelSize: 32))
        let image = try await makePipeline().image(for: request)

        #expect(image.cgImage?.width == 32)
        #expect(image.cgImage?.bitsPerComponent ?? 0 > 8)
        #expect(try Self.brightest(in: image) > 2)
    }

#if !targetEnvironment(simulator)
    @Test func thumbnailOfGainMapIsDecodedToHighDynamicRange() async throws {
        let request = makeRequest(gainMap, thumbnail: .init(maxPixelSize: 32))
        let image = try await makePipeline().image(for: request)

        #expect(image.cgImage?.bitsPerComponent ?? 0 > 8)
        #expect(try Self.brightest(in: image) > 2)
    }
#endif

    // MARK: - Processors

    @Test func processorsStartFromTheStandardImage() async throws {
        let processor = DecodedRangeProcessor()
        let inner = MockImageProcessor(id: "inner")
        _ = try await makePipeline().image(for: makeRequest(gainMap, processors: [inner, processor]))

        #expect(processor.decodedRanges == [.standard])
    }

    @Test func processedRequestsShareTheirImage() async throws {
        let pipeline = makePipeline()
        let processor = MockImageProcessor(id: "1")
        let high = makeRequest(pq, processors: [processor])
        let standard = makeRequest(pq, dynamicRange: .standard, processors: [processor])
        #expect(pipeline.cache.makeImageCacheKey(for: high) == pipeline.cache.makeImageCacheKey(for: standard))
        #expect(TaskLoadImageKey(high) == TaskLoadImageKey(standard))

        _ = try await pipeline.image(for: high)
        let response = try await pipeline.imageTask(with: standard).response

        #expect(response.cacheType == .memory)
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Caching

    @Test func memoryCacheKeepsTheRangesApart() async throws {
        let pipeline = makePipeline()
        let high = makeRequest(gainMap)
        let standard = makeRequest(gainMap, dynamicRange: .standard)

        #expect(pipeline.cache.makeImageCacheKey(for: high) != pipeline.cache.makeImageCacheKey(for: standard))

        _ = try await pipeline.image(for: high)

        #expect(pipeline.cache.cachedImage(for: high) != nil)
        #expect(pipeline.cache.cachedImage(for: standard, caches: [.memory]) == nil)
    }

    @Test func rangesShareTheDownloadButNotTheDecode() async throws {
        let observer = ImagePipelineObserver()
        let pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let high = makeRequest(pq)
        let standard = makeRequest(pq, dynamicRange: .standard)

        #expect(TaskFetchOriginalDataKey(high) == TaskFetchOriginalDataKey(standard))
        #expect(TaskFetchOriginalImageKey(high) != TaskFetchOriginalImageKey(standard))
        #expect(TaskLoadImageKey(high) != TaskLoadImageKey(standard))

        dataLoader.isSuspended = true
        async let first = pipeline.image(for: high)
        async let second = pipeline.image(for: standard)
        await waitUntil { observer.startedTaskCount == 2 }
        dataLoader.isSuspended = false
        let (highImage, standardImage) = try await (first, second)

        #expect(dataLoader.createdTaskCount == 1)
        #expect(highImage.cgImage?.bitsPerComponent != standardImage.cgImage?.bitsPerComponent || highImage !== standardImage)
    }

    @Test func loadedFromDiskInHighDynamicRange() async throws {
        _ = try await makePipeline().image(for: makeRequest(pq))
        imageCache.removeAll()

        let image = try await makePipeline().image(for: makeRequest(pq))

        #expect(dataLoader.createdTaskCount == 1)
        #expect(image.cgImage?.bitsPerComponent ?? 0 > 8)
        #expect(try Self.brightest(in: image) > 3)
    }

    @Test func encodedPolicyStoresTheOriginal() async throws {
        let pipeline = makePipeline { $0.dataCachePolicy = .storeEncodedImages }
        let request = makeRequest(gainMap)
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        #expect(dataCache.store == [pipeline.cache.makeDataCacheKey(for: request): gainMap])
    }

    @Test func standardRequestsStillEncode() async throws {
        let pipeline = makePipeline { $0.dataCachePolicy = .storeEncodedImages }
        let request = makeRequest(Test.data, dynamicRange: .standard)
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        let stored = try #require(dataCache.store[pipeline.cache.makeDataCacheKey(for: request)])
        #expect(stored != Test.data)
    }

    @Test(arguments: [ImagePipeline.DataCachePolicy.automatic, .storeAll, .storeEncodedImages, .storeOriginalData])
    func thumbnailIsNotStored(policy: ImagePipeline.DataCachePolicy) async throws {
        let pipeline = makePipeline { $0.dataCachePolicy = policy }
        let request = makeRequest(gainMap, thumbnail: .init(maxPixelSize: 32))
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        #expect(dataCache.store == [Test.url.absoluteString: gainMap])
    }

    @Test func thumbnailIgnoresTheStandardOneOnDisk() async throws {
        let pipeline = makePipeline { $0.dataCachePolicy = .automatic }
        let thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 32)
        let standard = makeRequest(pq, dynamicRange: .standard, thumbnail: thumbnail)
        _ = try await pipeline.image(for: standard)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()
        #expect(dataCache.store.count == 2) // The original and the encoded thumbnail
        imageCache.removeAll()

        let high = makeRequest(pq, thumbnail: thumbnail)
        let image = try await pipeline.image(for: high)

        #expect(pipeline.cache.makeDataCacheKey(for: high) != pipeline.cache.makeDataCacheKey(for: standard))
        #expect(image.cgImage?.bitsPerComponent ?? 0 > 8)
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Helpers

    /// Returns the largest component of the image in extended linear sRGB,
    /// where 1 is SDR white. `0` means that the image is black.
    private static func brightest(in image: PlatformImage) throws -> Float {
        let cgImage = try #require(image.cgImage)
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let context = try #require(CGContext(data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: 32, bytesPerRow: 0, space: space, bitmapInfo: info))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let count = cgImage.width * cgImage.height * 4
        let pixels = UnsafeBufferPointer(start: try #require(context.data).bindMemory(to: Float.self, capacity: count), count: count)
        return pixels.enumerated().reduce(0) { $1.offset % 4 == 3 ? $0 : max($0, $1.element) }
    }
}

/// Records the range of the image a processor starts from.
private final class DecodedRangeProcessor: ImageProcessing, @unchecked Sendable {
    private let lock = NSLock()
    private var ranges: [ImageRequest.DynamicRange] = []

    var decodedRanges: [ImageRequest.DynamicRange] { lock.withLock { ranges } }

    var identifier: String { "DecodedRangeProcessor" }

    func process(_ image: PlatformImage) -> PlatformImage? { image }

    func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
        lock.withLock { ranges.append(context.response.request.dynamicRange) }
        return container
    }
}

private final class DecompressionObserver: ImagePipeline.Delegate, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var decompressionCount: Int { lock.withLock { count } }

    func decompress(response: ImageResponse, request: ImageRequest, pipeline: ImagePipeline) -> ImageResponse {
        lock.withLock { count += 1 }
        return response
    }
}
