// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

/// Test how well image pipeline interacts with memory cache.
class ImagePipelineImageCacheTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var cache: MockImageCache!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        cache = MockImageCache()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
        }
    }

    func testThatImageIsLoaded() {
        expect(pipeline).toLoadImage(with: Test.request)
        wait()
    }

    // MARK: Caching

    func testCacheWrite() {
        // When
        expect(pipeline).toLoadImage(with: Test.request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNotNil(cache[Test.request])
    }

    func testCacheRead() {
        // Given
        cache[Test.request] = ImageContainer(image: Test.image)

        // When
        expect(pipeline).toLoadImage(with: Test.request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
        XCTAssertNotNil(cache[Test.request])
    }

    func testCacheWriteDisabled() {
        // Given
        var request = Test.request
        request.options.insert(.disableMemoryCacheWrites)

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNil(cache[Test.request])
    }

    func testMemoryCacheReadDisabled() {
        // Given
        cache[Test.request] = ImageContainer(image: Test.image)

        var request = Test.request
        request.options.insert(.disableMemoryCacheReads)

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNotNil(cache[Test.request])
    }

    func testReloadIgnoringCacheData() {
        // Given
        cache[Test.request] = ImageContainer(image: Test.image)

        var request = Test.request
        request.options.insert(.reloadIgnoringCachedData)

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNotNil(cache[Test.request])
    }
}

/// Make sure that cache layers are checked in the correct order and the
/// minimum necessary number of cache lookups are performed.
class ImagePipelineCacheLayerPriorityTests: XCTestCase {
    var pipeline: ImagePipeline!
    var dataLoader: MockDataLoader!
    var imageCache: MockImageCache!
    var dataCache: MockDataCache!
    var processorFactory: MockProcessorFactory!

    var request: ImageRequest!
    var intermediateRequest: ImageRequest!
    var processedImage: ImageContainer!
    var intermediateImage: ImageContainer!
    var originalRequest: ImageRequest!
    var originalImage: ImageContainer!

    override func setUp() {
        super.setUp()

        dataCache = MockDataCache()
        dataLoader = MockDataLoader()
        imageCache = MockImageCache()
        processorFactory = MockProcessorFactory()

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = imageCache
            $0.debugIsSyncImageEncoding = true
        }

        request = ImageRequest(url: Test.url, processors: [
            processorFactory.make(id: "1"),
            processorFactory.make(id: "2"),
        ])

        intermediateRequest = ImageRequest(url: Test.url, processors: [
            processorFactory.make(id: "1")
        ])

        originalRequest = ImageRequest(url: Test.url)

        do {
            let image = PlatformImage(data: Test.data)!
            image.nk_test_processorIDs = ["1", "2"]
            processedImage = ImageContainer(image: image)
        }

        do {
            let image = PlatformImage(data: Test.data)!
            image.nk_test_processorIDs = ["1"]
            intermediateImage = ImageContainer(image: image)
        }

        originalImage = ImageContainer(image: PlatformImage(data: Test.data)!)
    }

    func testGivenProcessedImageInMemoryCache() {
        // GIVEN
        imageCache[request] = processedImage

        // WHEN
        let record = expect(pipeline).toLoadImage(with: request)
        wait()
        XCTAssertTrue(record.image === processedImage.image)
        XCTAssertEqual(record.response?.cacheType, .memory)

        // THEN
        XCTAssertEqual(imageCache.readCount, 1)
        XCTAssertEqual(imageCache.writeCount, 1) // Initial write
        XCTAssertEqual(dataCache.readCount, 0)
        XCTAssertEqual(dataCache.writeCount, 0)
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
    }

    func testGivenProcessedImageInBothMemoryAndDiskCache() {
        // GIVEN
        pipeline.cache.storeCachedImage(processedImage, for: request, caches: [.all])

        // WHEN
        let record = expect(pipeline).toLoadImage(with: request)
        wait()
        XCTAssertTrue(record.image === processedImage.image)
        XCTAssertEqual(record.response?.cacheType, .memory)

        // THEN
        XCTAssertEqual(imageCache.readCount, 1)
        XCTAssertEqual(imageCache.writeCount, 1) // Initial write
        XCTAssertEqual(dataCache.readCount, 0)
        XCTAssertEqual(dataCache.writeCount, 1) // Initial write
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
    }

    func testGivenProcessedImageInDiskCache() {
        // GIVEN
        pipeline.cache.storeCachedImage(processedImage, for: request, caches: [.disk])

        // WHEN
        let record = expect(pipeline).toLoadImage(with: request)
        wait()
        XCTAssertNotNil(record.image)
        XCTAssertEqual(record.response?.cacheType, .disk)

        // THEN
        XCTAssertEqual(imageCache.readCount, 1)
        XCTAssertEqual(imageCache.writeCount, 1) // Initial write
        XCTAssertEqual(dataCache.readCount, 1)
        XCTAssertEqual(dataCache.writeCount, 1) // Initial write
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
    }

    func testGivenProcessedImageInDiskCacheAndIndermediateImageInMemoryCache() {
        // GIVEN
        pipeline.cache.storeCachedImage(processedImage, for: request, caches: [.disk])
        pipeline.cache.storeCachedImage(intermediateImage, for: intermediateRequest, caches: [.memory])

        // WHEN
        let record = expect(pipeline).toLoadImage(with: request)
        wait()
        XCTAssertNotNil(record.image)
        XCTAssertEqual(record.response?.cacheType, .disk)

        // THEN
        XCTAssertEqual(imageCache.readCount, 1)
        XCTAssertEqual(imageCache.writeCount, 2) // Initial write
        XCTAssertNotNil(imageCache[request])
        XCTAssertNotNil(imageCache[intermediateRequest])
        XCTAssertEqual(dataCache.readCount, 1)
        XCTAssertEqual(dataCache.writeCount, 1) // Initial write
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
    }

    func testGivenIndermediateImageInMemoryCache() {
        // GIVEN
        pipeline.cache.storeCachedImage(intermediateImage, for: intermediateRequest, caches: [.memory])

        // WHEN
        let record = expect(pipeline).toLoadImage(with: request)
        wait()
        XCTAssertEqual(record.image?.nk_test_processorIDs, ["1", "2"])
        XCTAssertEqual(record.response?.cacheType, .memory)

        // THEN
        XCTAssertEqual(imageCache.readCount, 2) // Processed + intermediate
        XCTAssertEqual(imageCache.writeCount, 2) // Initial write
        XCTAssertNotNil(imageCache[request])
        XCTAssertNotNil(imageCache[intermediateRequest])
        XCTAssertEqual(dataCache.readCount, 1) // Check original image
        XCTAssertEqual(dataCache.writeCount, 0)
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
    }

    func testGivenOriginalAndIntermediateImageInMemoryCache() {
        // GIVEN
        pipeline.cache.storeCachedImage(intermediateImage, for: intermediateRequest, caches: [.memory])
        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.memory])

        // WHEN
        let record = expect(pipeline).toLoadImage(with: request)
        wait()
        XCTAssertEqual(record.image?.nk_test_processorIDs, ["1", "2"])
        XCTAssertEqual(record.response?.cacheType, .memory)

        // THEN
        XCTAssertEqual(imageCache.readCount, 2) // Processed + intermediate
        XCTAssertEqual(imageCache.writeCount, 3) // Initial write + write processed
        XCTAssertNotNil(imageCache[originalRequest])
        XCTAssertNotNil(imageCache[request])
        XCTAssertNotNil(imageCache[intermediateRequest])
        XCTAssertEqual(dataCache.readCount, 1) // Check original image
        XCTAssertEqual(dataCache.writeCount, 0)
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
    }

    func testGivenOriginalImageInBothCaches() {
        // GIVEN
        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.all])

        // WHEN
        let record = expect(pipeline).toLoadImage(with: request)
        wait()
        XCTAssertEqual(record.image?.nk_test_processorIDs, ["1", "2"])
        XCTAssertEqual(record.response?.cacheType, .memory)

        // THEN
        XCTAssertEqual(imageCache.readCount, 3) // Processed + intermediate + original
        XCTAssertEqual(imageCache.writeCount, 2) // Processed + original
        XCTAssertNotNil(imageCache[originalRequest])
        XCTAssertNotNil(imageCache[request])
        XCTAssertEqual(dataCache.readCount, 1) // Processed
        XCTAssertEqual(dataCache.writeCount, 1) // Initial
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
    }

    func testGivenOriginalImageInDiskCache() {
        // GIVEN
        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.disk])

        // WHEN
        let record = expect(pipeline).toLoadImage(with: request)
        wait()
        XCTAssertEqual(record.image?.nk_test_processorIDs, ["1", "2"])
        XCTAssertEqual(record.response?.cacheType, .disk)

        // THEN
        XCTAssertEqual(imageCache.readCount, 3) // Processed + intermediate + original
        XCTAssertEqual(imageCache.writeCount, 1) // Processed
        XCTAssertNotNil(imageCache[request])
        XCTAssertEqual(dataCache.readCount, 2) // Processed + original
        XCTAssertEqual(dataCache.writeCount, 1) // Initial
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
    }

    // MARK: ImageRequest.Options

    func testGivenOriginalImageInDiskCacheAndDiskReadsDisabled() {
        // GIVEN
        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.disk])

        // WHEN
        request.options.insert(.disableDiskCacheReads)
        let record = expect(pipeline).toLoadImage(with: request)
        wait()
        XCTAssertEqual(record.image?.nk_test_processorIDs, ["1", "2"])
        XCTAssertNil(record.response?.cacheType)

        // THEN
        XCTAssertEqual(imageCache.readCount, 3) // Processed + intermediate + original
        XCTAssertEqual(imageCache.writeCount, 1) // Processed
        XCTAssertNotNil(imageCache[request])
        XCTAssertEqual(dataCache.readCount, 0) // Processed + original
        XCTAssertEqual(dataCache.writeCount, 2) // Initial + processed
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
    }

    func testGivenNoImageDataInDiskCacheAndDiskWritesDisabled() {
        // WHEN
        request.options.insert(.disableDiskCacheWrites)
        let record = expect(pipeline).toLoadImage(with: request)
        wait()
        XCTAssertEqual(record.image?.nk_test_processorIDs, ["1", "2"])
        XCTAssertNil(record.response?.cacheType)

        // THEN
        XCTAssertEqual(imageCache.readCount, 3) // Processed + intermediate + original
        XCTAssertEqual(imageCache.writeCount, 1) // Processed
        XCTAssertNotNil(imageCache[request])
        XCTAssertEqual(dataCache.readCount, 2) // Processed + original
        XCTAssertEqual(dataCache.writeCount, 0)
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
    }

    func testGivenTwoRequestWhereOnlyOneHasDiskWritesDisabled() {
        // WHEN
        pipeline.resgiterMultipleRequests {
            request.options.insert(.disableDiskCacheWrites)
            expect(pipeline).toLoadImage(with: request)
            request.options.remove(.disableDiskCacheWrites)
            expect(pipeline).toLoadImage(with: request)
        }
        wait()

        // THEN
        XCTAssertEqual(imageCache.readCount, 6) // Processed + intermediate + original
        XCTAssertEqual(imageCache.writeCount, 2) // Processed
        XCTAssertNotNil(imageCache[request])
        XCTAssertEqual(dataCache.readCount, 4) // Processed + original
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
    }
}
