// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

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
        expect(pipeline).toLoadImage(with: Test.request) { _ in
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
            },
            completion: { _ in }
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
        let task = pipeline.loadImage(with: request) { _ in
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

    func testTaskProgressIsUpdated() {
        // Given
        let request = ImageRequest(url: Test.url)

        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let expectedProgress = expectProgress([(10, 20), (20, 20)])

        var task: ImageTask!
        task = pipeline.loadImage(
            with: request,
            progress: { _, completed, total in
                // Then
                XCTAssertTrue(Thread.isMainThread)
                expectedProgress.received((task.completedUnitCount, task.totalUnitCount))
            },
            completion: { _ in }
        )

        wait()
    }

    // MARK: - Callback Queues

    func testChangingCallbackQueueLoadImage() {
        // Given
        let queue = DispatchQueue(label: "testChangingCallbackQueue")
        let queueKey = DispatchSpecificKey<Void>()
        queue.setSpecific(key: queueKey, value: ())

        // When/Then
        let expectation = self.expectation(description: "Image Loaded")
        pipeline.loadImage(with: Test.url, queue: queue, progress: { _, _, _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
        }, completion: { _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
            expectation.fulfill()
        })
        wait()
    }

    // MARK: - Animated Images

    func testAnimatedImagesArentProcessed() {
        // Given
        ImagePipeline.Configuration._isAnimatedImageDataEnabled = true

        dataLoader.results[Test.url] = .success(
            (Test.data(name: "cat", extension: "gif"), Test.urlResponse)
        )

        let processor = ImageProcessors.Anonymous(id: "1") { _ in
            XCTFail()
            return nil
        }
        let request = ImageRequest(url: Test.url, processors: [processor])

        // Then
        expect(pipeline).toLoadImage(with: request) { result in
            let image = result.value?.image
            XCTAssertNotNil(image?._animatedImageData)
        }
        wait()

        ImagePipeline.Configuration._isAnimatedImageDataEnabled = false
    }

    // MARK: - Updating Priority

    func testDataLoadingPriorityUpdated() {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = Test.request
        XCTAssertEqual(request.priority, .normal)

        let observer = expect(queue).toEnqueueOperationsWithCount(1)

        let task = pipeline.loadImage(with: request) { _ in }
        wait() // Wait till the operation is created.

        // When/Then
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        expect(operation).toUpdatePriority()
        task.priority = .high

        wait()
    }

    func testDecodingPriorityUpdated() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in MockImageDecoder(name: "test") }
        }

        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        let request = Test.request
        XCTAssertEqual(request.priority, .normal)

        let observer = expect(queue).toEnqueueOperationsWithCount(1)

        let task = pipeline.loadImage(with: request) { _ in }
        wait() // Wait till the operation is created.

        // When/Then
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        expect(operation).toUpdatePriority()
        task.priority = .high

        wait()
    }

    func testProcessingPriorityUpdated() {
        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        let request = ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "1", { $0 })])
        XCTAssertEqual(request.priority, .normal)

        let observer = expect(queue).toEnqueueOperationsWithCount(1)

        let task = pipeline.loadImage(with: request) { _ in }
        wait() // Wait till the operation is created.

        // When/Then
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        expect(operation).toUpdatePriority()
        task.priority = .high

        wait()
    }

    // MARK: - Cancellation

    func testDataLoadingOperationCancelled() {
        dataLoader.queue.isSuspended = true

        expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.loadImage(with: Test.request) { _ in
            XCTFail()
        }
        wait() // Wait till operation is created

        expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
        task.cancel()
        wait()
    }

    func testDecodingOperationCancelled() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in MockImageDecoder(name: "test") }
        }

        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        let observer = self.expect(queue).toEnqueueOperationsWithCount(1)

        let request = Test.request

        let task = pipeline.loadImage(with: request) { _ in
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

        let processor = ImageProcessors.Anonymous(id: "1") {
            XCTFail()
            return $0
        }
        let request = ImageRequest(url: Test.url, processors: [processor])

        let task = pipeline.loadImage(with: request) { _ in
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
            $0.makeImageDecoder = { _ in
                MockAnonymousImageDecoder { _, _ in
                    return image
                }
            }
            $0.imageCache = nil

            $0.isDecompressionEnabled = false
        }

        // When
        expect(pipeline).toLoadImage(with: Test.request) { result in
            guard let output = result.value?.image else {
                return XCTFail("Expected image to be loaded")
            }

            XCTAssertTrue(output === image)

            let isDecompressionNeeded = ImageDecompression.isDecompressionNeeded(for: output)
            XCTAssertEqual(isDecompressionNeeded, true)
        }
        wait()
    }

    func testDecompression() {
        let image = Test.image

        // Given the pipeline which returns a predefined image
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.makeImageDecoder = { _ in
                MockAnonymousImageDecoder { _, _ in
                    return image
                }
            }
            $0.imageCache = nil
        }

        // When
        expect(pipeline).toLoadImage(with: Test.request) { result in
            guard let output = result.value?.image else {
                return XCTFail("Expected image to be loaded")
            }

            XCTAssertTrue(output !== image)

            XCTAssertNil(ImageDecompression.isDecompressionNeeded(for: output))
        }
        wait()
    }

    func testDecompressionNotPerformedWhenProcessorWasApplied() {
        // Given request with scaling processor
        let request = ImageRequest(url: Test.url, processors: [
            ImageProcessors.Resize(size: CGSize(width: 40, height: 40), contentMode: .aspectFit)
        ])

        expect(pipeline).toLoadImage(with: request) { result in
            guard let image = result.value?.image else {
                return XCTFail("Expected image to be loaded")
            }

            // Expect decompression to not be performed
            let isDecompressionNeeded = ImageDecompression.isDecompressionNeeded(for: image)
            XCTAssertNil(isDecompressionNeeded)
        }
        wait()
    }

    func testDecompressionPerformedWhenProcessorIsAppliedButDoesNothing() {
        // Given request with scaling processor
        let request = ImageRequest(url: Test.url, processors: [MockEmptyImageProcessor()])

        expect(pipeline).toLoadImage(with: request) { result in
            guard let image = result.value?.image else {
                return XCTFail("Expected image to be loaded")
            }

            // Expect decompression to be performed (processor was applied but it did nothing)
            XCTAssertNil(ImageDecompression.isDecompressionNeeded(for: image))
        }
        wait()
    }

    #endif

    // MARK: - CacheKey

    func testCacheKeyForRequest() {
        let request = Test.request
        XCTAssertEqual(pipeline.cache.makeDataCacheKey(for: request), Test.url.absoluteString)
    }

    func testCacheKeyForRequestWithProcessors() {
        var request = Test.request
        request.processors = [ImageProcessors.Anonymous(id: "1", { $0 })]
        XCTAssertEqual(pipeline.cache.makeDataCacheKey(for: request), Test.url.absoluteString + "1")
    }

    // MARK: - Invalidate

    func testWhenInvalidatedTasksAreCancelled() {
        dataLoader.queue.isSuspended = true

        expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        pipeline.loadImage(with: Test.request) { _ in
            XCTFail()
        }
        wait() // Wait till operation is created

        expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
        pipeline.invalidate()
        wait()
    }

    func testWhenInvalidatedNewTasksCantBeStarted() {
        dataLoader.queue.isSuspended = true
        pipeline.invalidate()

        let didStartExpectation = expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        didStartExpectation.isInverted = true

        pipeline.loadImage(with: Test.request) { _ in
            XCTFail()
        }

        waitForExpectations(timeout: 0.02, handler: nil)
    }

    // MARK: Error Handling

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
            $0.makeImageDecoder = { _ in
                return MockFailingDecoder()
            }
            $0.imageCache = nil
        }

        // When/Then
        expect(pipeline).toFailRequest(Test.request, with: .decodingFailed)
        wait()
    }

    func testProcessingFailedErrorReturned() {
        // GIVEN
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            return
        }

        let request = ImageRequest(url: Test.url, processors: [MockFailingProcessor()])

        // WHEN/THEM
        expect(pipeline).toFailRequest(request) { result in
            guard case .failure(let error) = result,
                  case .processingFailed(let processor) = error else {
                return XCTFail()
            }
            XCTAssertTrue(processor is MockFailingProcessor)
        }
        wait()
    }

    func testImageContainerUserInfo() { // Just to make sure we have 100% coverage
        // WHEN
        let container = ImageContainer(image: Test.image, type: nil, isPreview: false, data: nil, userInfo: [.init("a"): 1])

        // THEN
        XCTAssertEqual(container.userInfo["a"] as? Int, 1)
    }

    func testErrorDescription() {
        XCTAssertFalse(ImagePipeline.Error.dataLoadingFailed(URLError(.unknown)).description.isEmpty) // Just padding here
        XCTAssertFalse(ImagePipeline.Error.decodingFailed.description.isEmpty)

        let processor = ImageProcessors.Resize(width: 100, unit: .pixels)
        let error = ImagePipeline.Error.processingFailed(processor)
        let expected = "Failed to process the image using processor Resize(size: (100.0, 9999.0) pixels, contentMode: .aspectFit, crop: false, upscale: false)"
        XCTAssertEqual(error.description, expected)
        XCTAssertEqual("\(error)", expected)

        XCTAssertNil(error.dataLoadingError)
    }

    // MARK: Misc

    #if !os(macOS)
    func testOverridingImageScale() throws {
        // GIVEN
        let request = ImageRequest(url: Test.url, userInfo: [.scaleKey: 7])

        // WHEN
        let record = expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN
        let image = try XCTUnwrap(record.image)
        XCTAssertEqual(image.scale, 7)
    }

    func testOverridingImageScaleWithFloat() throws {
        // GIVEN
        let request = ImageRequest(url: Test.url, userInfo: [.scaleKey: 7.0])

        // WHEN
        let record = expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN
        let image = try XCTUnwrap(record.image)
        XCTAssertEqual(image.scale, 7)
    }
    #endif
}
