// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

@ImagePipelineActor
@Suite class ImagePipelineDataCachePolicyTests {
    var dataLoader: MockDataLoader!
    var dataCache: MockDataCache!
    var pipeline: ImagePipeline!
    var encoder: MockImageEncoder!
    var processorFactory: MockProcessorFactory!
    var request: ImageRequest!

    init() async throws {
        dataCache = MockDataCache()
        dataLoader = MockDataLoader()
        let encoder = MockImageEncoder(result: Test.data(name: "fixture-tiny", extension: "jpeg"))
        self.encoder = encoder

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.makeImageEncoder = { _ in encoder }
            $0.debugIsSyncImageEncoding = true
        }

        processorFactory = MockProcessorFactory()

        request = ImageRequest(url: Test.url, processors: [processorFactory.make(id: "1")])
    }

    // MARK: - Basics

    @Test func processedImageLoadedFromDataCache() async throws {
        // Given processed image data stored in data cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When/Then
        _ = try await pipeline.image(for: request)

        // Then
        #expect(processorFactory.numberOfProcessorsApplied == 0, "Expected no processors to be applied")
    }

#if !os(macOS)
    @Test func processedImageIsDecompressed() async throws {
        // Given processed image data stored in data cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When
        let image = try await pipeline.image(for: request)

        // Then
        #expect(ImageDecompression.isDecompressionNeeded(for: image) == nil)
    }

    @Test func processedImageIsStoredInMemoryCache() async throws {
        // Given processed image data stored in data cache
        let cache = MockImageCache()
        pipeline = pipeline.reconfigured {
            $0.imageCache = cache
        }
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When
        _ = try await pipeline.image(for: request)

        // Then decompressed image is stored in disk cache
        let container = cache[request]
        #expect(container != nil)

        let image = try #require(container?.image)
        #expect(ImageDecompression.isDecompressionNeeded(for: image) == nil)
    }

    @Test func processedImageNotDecompressedWhenDecompressionDisabled() async throws {
        // Given pipeline with decompression disabled
        pipeline = pipeline.reconfigured {
            $0.isDecompressionEnabled = false
        }

        // Given processed image data stored in data cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When
        let image = try await pipeline.image(for: request)

        // Then
        let isDecompressionNeeded = ImageDecompression.isDecompressionNeeded(for: image)
        #expect(isDecompressionNeeded == true, "Expected image to still be marked as non decompressed")
    }
#endif

    // MARK: DataCachPolicy.automatic

    @Test func policyAutomaticGivenRequestWithProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // Given request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // When
        _ = try await pipeline.image(for: request)

        // Then encoded processed image is stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyAutomaticGivenRequestWithoutProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // Given request without a processor
        let request = ImageRequest(url: Test.url)

        // When
        _ = try await pipeline.image(for: request)

        // Then original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyAutomaticGivenTwoRequests() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // When
        async let task1 = pipeline.image(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        async let task2 = pipeline.image(for: ImageRequest(url: Test.url))
        _ = try await (task1, task2)

        // Then
        // encoded processed image is stored in disk cache
        // original image data is stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 2)
        #expect(dataCache.store.count == 2)
    }

    @Test func policyAutomaticGivenOriginalImageInMemoryCache() async throws {
        // Given
        let imageCache = MockImageCache()
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
            $0.imageCache = imageCache
        }
        imageCache[ImageRequest(url: Test.url)] = Test.container

        // When
        _ = try await pipeline.image(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))

        // Then
        // encoded processed image is stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
        #expect(dataLoader.createdTaskCount == 0)
    }

    // MARK: DataCachPolicy.storeEncodedImages

    @Test func policyStoreEncodedImagesGivenRequestWithProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // Given request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // When
        _ = try await pipeline.image(for: request)

        // Then encoded processed image is stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreEncodedImagesGivenRequestWithoutProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // Given request without a processor
        let request = ImageRequest(url: Test.url)

        // When
        _ = try await pipeline.image(for: request)

        // Then
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreEncodedImagesGivenTwoRequests() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // When
        async let task1 = pipeline.image(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        async let task2 = pipeline.image(for: ImageRequest(url: Test.url))
        _ = try await (task1, task2)

        // Then
        // encoded processed image is stored in disk cache
        // encoded original image is stored in disk cache
        #expect(encoder.encodeCount == 2)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 2)
        #expect(dataCache.store.count == 2)
    }

    // MARK: DataCachPolicy.storeOriginalData

    @Test func policyStoreOriginalDataGivenRequestWithProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // Given request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // When
        _ = try await pipeline.image(for: request)

        // Then encoded processed image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreOriginalDataGivenRequestWithoutProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // Given request without a processor
        let request = ImageRequest(url: Test.url)

        // When
        _ = try await pipeline.image(for: request)

        // Then original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreOriginalDataGivenTwoRequests() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // When
        async let task1 = pipeline.image(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        async let task2 = pipeline.image(for: ImageRequest(url: Test.url))
        _ = try await (task1, task2)

        // Then
        // encoded processed image is stored in disk cache
        // encoded original image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    // MARK: DataCachPolicy.storeAll

    @Test func policyStoreAllGivenRequestWithProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // Given request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // When
        _ = try await pipeline.image(for: request)

        // Then encoded processed image is stored in disk cache and
        // original image data stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 2)
        #expect(dataCache.store.count == 2)
    }

    @Test func policyStoreAllGivenRequestWithoutProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // Given request without a processor
        let request = ImageRequest(url: Test.url)

        // When
        _ = try await pipeline.image(for: request)

        // Then original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreAllGivenTwoRequests() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // When
        async let task1 = pipeline.image(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        async let task2 = pipeline.image(for: ImageRequest(url: Test.url))
        _ = try await (task1, task2)

        // Then
        // encoded processed image is stored in disk cache
        // original image data is stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 2)
        #expect(dataCache.store.count == 2)
    }

    // MARK: Local Resources

    @Test func imagesFromLocalStorageNotCached() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // Given request without a processor
        let request = ImageRequest(url: Test.url(forResource: "fixture", extension: "jpeg"))

        // When
        _ = try await pipeline.image(for: request)

        // Then original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    @Test func processedImagesFromLocalStorageAreNotCached() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // Given request with a processor
        let request = ImageRequest(url: Test.url(forResource: "fixture", extension: "jpeg") ,processors: [.resize(width: 100)])

        // When
        _ = try await pipeline.image(for: request)

        // Then original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    @Test func imagesFromMemoryNotCached() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // Given request without a processor
        let request = ImageRequest(url: Test.url(forResource: "fixture", extension: "jpeg"))

        // When
        _ = try await pipeline.image(for: request)

        // Then original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    // TODO: this fails because there is too few thread hops
    @Test func imagesFromData() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // Given request without a processor
        let data = Test.data(name: "fixture", extension: "jpeg")
        let url = URL(string: "data:image/jpeg;base64,\(data.base64EncodedString())")
        let request = ImageRequest(url: url)

        // When
        _ = try await pipeline.image(for: request)

        // Then original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    // MARK: Misc

    @Test func setCustomImageEncoder() async throws {
        struct MockImageEncoder: ImageEncoding, @unchecked Sendable {
            let closure: (PlatformImage) -> Data?

            func encode(_ image: PlatformImage) -> Data? {
                return closure(image)
            }
        }

        // Given
        var isCustomEncoderCalled = false
        let encoder = MockImageEncoder { _ in
            isCustomEncoderCalled = true
            return nil
        }

        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
            $0.makeImageEncoder = { _ in
                return encoder
            }
        }

        // When
        _ = try await pipeline.image(for: request)

        // Then
        #expect(isCustomEncoderCalled)
        #expect(self.dataCache.cachedData(for: Test.url.absoluteString + "1") == nil, "Expected processed image data to not be stored")
    }

    // MARK: Integration with Thumbnail Feature

    @Test func originalDataStoredWhenThumbnailRequested() async throws {
        // Given
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])

        // When
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataCache.containsData(for: "http://test.com/example.jpeg"))
    }
}
