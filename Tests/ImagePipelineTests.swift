// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    
    override func setUp() {
        super.setUp()
        
        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Completion

    func testCompletionCalledAsynchronouslyOnMainThread() {
        var isCompleted = false
        expect(pipeline).toLoadImage(with: Test.request) { _, _ in
            XCTAssert(Thread.isMainThread)
            isCompleted = true
        }
        XCTAssertFalse(isCompleted)
        wait()
    }

    // MARK: - Progress

    func testProgressClosureIsCalled() {
        // Given
        let request = ImageRequest(url: Test.url)

        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let expectedProgress = expectProgress([(10, 20), (20, 20)])

        pipeline.loadImage(
            with: request,
            progress: { _, completed, total in
                // Then
                XCTAssertTrue(Thread.isMainThread)
                expectedProgress.received((completed, total))
            }
        )

        wait()
    }

    func testProgressObjectIsUpdated() {
        // Given
        let request = Test.request

        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let expectTaskFinished = self.expectation(description: "Task finished")
        let task = pipeline.loadImage(with: request) { _, _ in
            expectTaskFinished.fulfill()
        }

        // Then
        self.expect(values: [20], for: task.progress, keyPath: \.totalUnitCount) { _, _ in
            XCTAssertTrue(Thread.isMainThread)
        }
        self.expect(values: [10, 20], for: task.progress, keyPath: \.completedUnitCount) { _, _ in
            XCTAssertTrue(Thread.isMainThread)
        }

        wait()
    }

    // MARK: - Configuration

    func testOverridingProcessor() {
        // Given
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageProcessor = { _, _ in
                AnyImageProcessor(MockImageProcessor(id: "processorFromOptions"))
            }
        }
        let request = Test.request.processed(with: MockImageProcessor(id: "processorFromRequest"))

        // Then
        expect(pipeline).toLoadImage(with: request) { response, _ in
            XCTAssertEqual(response?.image.nk_test_processorIDs.count, 1)
            XCTAssertEqual(response?.image.nk_test_processorIDs.first, "processorFromOptions")
        }
        wait()
    }

    // MARK: - Animated Images

    func testAnimatedImagesArentProcessed() {
        // Given
        ImagePipeline.Configuration.isAnimatedImageDataEnabled = true

        dataLoader.results[Test.url] = .success(
            (Test.data(name: "cat", extension: "gif"), Test.urlResponse)
        )

        let request = Test.request.processed(key: "1") { _ in
            XCTFail()
            return nil
        }

        // Then
        expect(pipeline).toLoadImage(with: request) { response, _ in
            XCTAssertNotNil(response?.image.animatedImageData)
        }
        wait()

        ImagePipeline.Configuration.isAnimatedImageDataEnabled = false
    }

    // MARK: - Updating Priority

    func testDataLoadingPriorityUpdated() {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = Test.request
        XCTAssertEqual(request.priority, .normal)

        let observer = self.expect(queue).toEnqueueOperationsWithCount(1)

        let task = pipeline.loadImage(with: request)
        wait() // Wait till the operation is created.

        // When/Then
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        expect(operation).toUpdatePriority()
        task.setPriority(.high)

        wait()
    }

    func testDecodingPriorityUpdated() {
        // Given
        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        let request = Test.request
        XCTAssertEqual(request.priority, .normal)

        let observer = self.expect(queue).toEnqueueOperationsWithCount(1)

        let task = pipeline.loadImage(with: request)
        wait() // Wait till the operation is created.

        // When/Then
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        expect(operation).toUpdatePriority()
        task.setPriority(.high)

        wait()
    }

    func testProcessingPriorityUpdated() {
        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        let request = Test.request.processed(key: "1") { $0 }
        XCTAssertEqual(request.priority, .normal)

        let observer = self.expect(queue).toEnqueueOperationsWithCount(1)

        let task = pipeline.loadImage(with: request)
        wait() // Wait till the operation is created.

        // When/Then
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        expect(operation).toUpdatePriority()
        task.setPriority(.high)

        wait()
    }

    // MARK: - Cancellation

    func testDataLoadingOperationCancelled() {
        dataLoader.queue.isSuspended = true

        expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.loadImage(with: Test.request) { (_, _) in
            XCTFail()
        }
        wait() // Wait till operation is created

        expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
        task.cancel()
        wait()
    }

    func testDecodingOperationCancelled() {
        // Given
        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        let observer = self.expect(queue).toEnqueueOperationsWithCount(1)

        let request = Test.request

        let task = pipeline.loadImage(with: request) { (_, _) in
            XCTFail()
        }
        wait() // Wait till operation is created

        // When/Then
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        expect(operation).toCancel()

        task.cancel()

        wait()
    }

    func testProcessingOperationCancelled() {
        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        let observer = self.expect(queue).toEnqueueOperationsWithCount(1)

        let request = Test.request.processed(key: "1") {
            XCTFail()
            return $0
        }

        let task = pipeline.loadImage(with: request) { (_, _) in
            XCTFail()
        }
        wait() // Wait till operation is created

        // When/Then
        let operation = observer.operations.first
        XCTAssertNotNil(operation)
        expect(operation!).toCancel()

        task.cancel()

        wait()
    }

    // MARK: Decompression

    #if !os(macOS)

    func testDisablingDecompression() {
        let image = Test.image

        // Given the pipeline which returns a predefined image and which
        // has decompression disabled
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageDecoder = { _ in
                MockAnonymousImageDecoder { _, _ in
                    return image
                }
            }
            $0.imageCache = nil

            $0.isDecompressionEnabled = false
        }

        // When
        expect(pipeline).toLoadImage(with: Test.request, completion: { response, _ in
            let output = response!.image

            XCTAssertTrue(output === image)

            let isDecompressionNeeded = ImageDecompression.isDecompressionNeeded(for: output)
            XCTAssertEqual(isDecompressionNeeded, true)
        })
        wait()
    }

    func testDecompression() {
        let image = Test.image

        // Given the pipeline which returns a predefined image
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageDecoder = { _ in
                MockAnonymousImageDecoder { _, _ in
                    return image
                }
            }
            $0.imageCache = nil
        }

        // When
        expect(pipeline).toLoadImage(with: Test.request, completion: { response, _ in
            let output = response!.image

            XCTAssertTrue(output !== image)

            let isDecompressionNeeded = ImageDecompression.isDecompressionNeeded(for: output)
            XCTAssertEqual(isDecompressionNeeded, false)
        })
        wait()
    }

    func testDecompressionNotPerformedWhenProcessorWasApplied() {
        // Given request with scaling processor
        var request = Test.request
        request.processor = AnyImageProcessor(ImageScalingProcessor(targetSize: CGSize(width: 40, height: 40), contentMode: .aspectFit))

        expect(pipeline).toLoadImage(with: request) { response, _ in
            let image = response!.image

            // Expect decompression to not be performed
            let isDecompressionNeeded = ImageDecompression.isDecompressionNeeded(for: image)
            XCTAssertNil(isDecompressionNeeded)
        }
        wait()
    }

    func testDecompressionPerformedWhenProcessorIsAppliedButDoesnNothing() {
        // Given request with scaling processor
        var request = Test.request
        request.processor = AnyImageProcessor(MockEmptyImageProcessor())

        expect(pipeline).toLoadImage(with: request) { response, _ in
            let image = response!.image

            // Expect decompression to be performed (processor was applied but it did nothing)
            let isDecompressionNeeded = ImageDecompression.isDecompressionNeeded(for: image)
            XCTAssertEqual(isDecompressionNeeded, false)
        }
        wait()
    }

    #endif

    // MARK: Disabling Decoding

    func testDisablingDecoding() {
        // Given the pipeline successfully returning image data
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageDecoder = { _ in
                XCTFail("The pipeline tried to decode the image data")
                return ImageDecoder()
            }
            $0.imageCache = nil
        }

        // Given the request with disabled decoding
        let request = Test.request.mutated {
            $0.isDecodingDisabled = true
        }

        // When the image data is loaded
        // Expect pipeline to skip decoding and return .decodingFailded error
        expect(pipeline).toFailRequest(request, with: .decodingFailed)
        wait()
    }
}

/// Test how well image pipeline interacts with memory cache.
class ImagePipelineMemoryCacheTests: XCTestCase {
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
        XCTAssertNotNil(cache.cachedResponse(for: Test.request))
    }

    func testCacheRead() {
        // Given
        cache.storeResponse(ImageResponse(image: Test.image, urlResponse: nil, scanNumber: nil), for: Test.request)

        // When
        expect(pipeline).toLoadImage(with: Test.request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
        XCTAssertNotNil(cache.cachedResponse(for: Test.request))
    }

    func testCacheWriteDisabled() {
        // Given
        let request = Test.request.mutated {
            $0.memoryCacheOptions.isWriteAllowed = false
        }

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNil(cache.cachedResponse(for: Test.request))
    }

    func testCacheReadDisabled() {
        // Given
        cache.storeResponse(ImageResponse(image: Test.image, urlResponse: nil, scanNumber: nil), for: Test.request)

        let request = Test.request.mutated {
            $0.memoryCacheOptions.isReadAllowed = false
        }

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNotNil(cache.cachedResponse(for: Test.request))
    }
}

class ImagePipelineErrorHandlingTests: XCTestCase {
    func testDataLoadingFailedErrorReturned() {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        let expectedError = NSError(domain: "t", code: 23, userInfo: nil)
        dataLoader.results[Test.url] = .failure(expectedError)

        // When/Then
        expect(pipeline).toFailRequest(Test.request, with: .dataLoadingFailed(expectedError))
        wait()
    }

    func testDecodingFailedErrorReturned() {
        // Given
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageDecoder = { _ in
                return MockFailingDecoder()
            }
            $0.imageCache = nil
        }

        // When/Then
        expect(pipeline).toFailRequest(Test.request, with: .decodingFailed)
        wait()
    }

    func testProcessingFailedErrorReturned() {
        // Given
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            return
        }

        let request = Test.request.processed(with: MockFailingProcessor())

        // When/Then
        expect(pipeline).toFailRequest(request, with: .processingFailed)
        wait()
    }
}
