// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import XCTest
import Combine
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
                expectedProgress.received((task.progress.completed, task.progress.total))
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
        pipeline.loadImage(with: Test.request, queue: queue, progress: { _, _, _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
        }, completion: { _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
            expectation.fulfill()
        })
        wait()
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
    
    func testDisablingDecompression() async throws {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.isDecompressionEnabled = false
        }
        
        // WHEN
        let image = try await pipeline.image(for: Test.url)
        
        // THEN
        XCTAssertEqual(true, ImageDecompression.isDecompressionNeeded(for: image))
    }
    
    func testDisablingDecompressionForIndividualRequest() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url, options: [.skipDecompression])
        
        // WHEN
        let image = try await pipeline.image(for: request)
        
        // THEN
        XCTAssertEqual(true, ImageDecompression.isDecompressionNeeded(for: image))
    }
    
    func testDecompressionPerformed() async throws {
        // WHEN
        let image = try await pipeline.image(for: Test.request)
        
        // THEN
        XCTAssertNil(ImageDecompression.isDecompressionNeeded(for: image))
    }
    
    func testDecompressionNotPerformedWhenProcessorWasApplied() async throws {
        // GIVEN request with scaling processor
        let input = Test.image
        pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in MockAnonymousImageDecoder(output: input) }
        }
        
        let request = ImageRequest(url: Test.url, processors: [
            .resize(size: CGSize(width: 40, height: 40))
        ])
        
        // WHEN
        _ = try await pipeline.image(for: request)
        
        // THEN
        XCTAssertEqual(true, ImageDecompression.isDecompressionNeeded(for: input))
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
    
    // MARK: - Thubmnail

    func testThatThumbnailIsGenerated() {
        // GIVEN
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])
        
        // WHEN
        expect(pipeline).toLoadImage(with: request) { result in
            // THEN
            guard let image = result.value?.image else {
                return XCTFail()
            }
            XCTAssertEqual(image.sizeInPixels, CGSize(width: 400, height: 300))
        }
        wait()
    }
    
    func testThumbnailIsGeneratedOnDecodingQueue() {
        // GIVEN
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])
        
        // WHEN/THEN
        expect(pipeline.configuration.imageDecodingQueue).toEnqueueOperationsWithCount(1)
        expect(pipeline).toLoadImage(with: request)
        wait()
    }
    
#if os(iOS)
    func testThumnbailIsntDecompressed() {
        pipeline.configuration.imageDecompressingQueue.isSuspended = true
        
        // GIVEN
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])
        
        // WHEN/THEN
        expect(pipeline).toLoadImage(with: request)
        wait()
    }
#endif
    
    // MARK: - CacheKey
    
    func testCacheKeyForRequest() {
        let request = Test.request
        XCTAssertEqual(pipeline.cache.makeDataCacheKey(for: request), "http://test.com")
    }
    
    func testCacheKeyForRequestWithProcessors() {
        var request = Test.request
        request.processors = [ImageProcessors.Anonymous(id: "1", { $0 })]
        XCTAssertEqual(pipeline.cache.makeDataCacheKey(for: request), "http://test.com1")
    }
    
    func testCacheKeyForRequestWithThumbnail() {
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])
        XCTAssertEqual(pipeline.cache.makeDataCacheKey(for: request), "http://test.comcom.github/kean/nuke/thumbnail?maxPixelSize=400.0,options=truetruetruetrue")
    }

    func testCacheKeyForRequestWithThumbnailFlexibleSize() {
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFit)
        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])
        XCTAssertEqual(pipeline.cache.makeDataCacheKey(for: request), "http://test.comcom.github/kean/nuke/thumbnail?width=400.0,height=400.0,contentMode=.aspectFit,options=truetruetruetrue")
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
    
    func testThatInvalidatedTasksFailWithError() async throws {
        // WHEN
        pipeline.invalidate()
        
        // THEN
        do {
            _ = try await pipeline.image(for: Test.request)
            XCTFail()
        } catch {
            XCTAssertEqual(error as? ImagePipeline.Error, .pipelineInvalidated)
        }
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
        expect(pipeline).toFailRequest(Test.request, with: .dataLoadingFailed(error: expectedError))
        wait()
    }
    
    func testDataLoaderReturnsEmptyData() {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        
        dataLoader.results[Test.url] = .success((Data(), Test.urlResponse))
        
        // When/Then
        expect(pipeline).toFailRequest(Test.request, with: .dataIsEmpty)
        wait()
    }
    
    func testDecoderNotRegistered() {
        // Given
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.makeImageDecoder = { _ in
                nil
            }
            $0.imageCache = nil
        }
        
        expect(pipeline).toFailRequest(Test.request) { result in
            guard let error = result.error else {
                return XCTFail("Expected error")
            }
            guard case let .decoderNotRegistered(context) = error else {
                return XCTFail("Expected .decoderNotRegistered")
            }
            XCTAssertEqual(context.request.url, Test.request.url)
            XCTAssertEqual(context.data.count, 22789)
            XCTAssertTrue(context.isCompleted)
            XCTAssertEqual(context.urlResponse?.url, Test.url)
        }
        wait()
    }
    
    func testDecodingFailedErrorReturned() async {
        // Given
        let decoder = MockFailingDecoder()
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.makeImageDecoder = { _ in decoder }
            $0.imageCache = nil
        }
        
        // When/Then
        do {
            _ = try await pipeline.image(for: Test.request)
            XCTFail("Expected failure")
        } catch {
            if case let .decodingFailed(failedDecoder, context, error) = error as? ImagePipeline.Error {
                XCTAssertTrue((failedDecoder as? MockFailingDecoder) === decoder)
                
                XCTAssertEqual(context.request.url, Test.request.url)
                XCTAssertEqual(context.data, Test.data)
                XCTAssertTrue(context.isCompleted)
                XCTAssertEqual(context.urlResponse?.url, Test.url)
                
                XCTAssertEqual(error as? MockError, MockError(description: "decoder-failed"))
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testProcessingFailedErrorReturned() {
        // GIVEN
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
        }
        
        let request = ImageRequest(url: Test.url, processors: [MockFailingProcessor()])
        
        // WHEN/THEN
        expect(pipeline).toFailRequest(request) { result in
            guard case .failure(let error) = result,
                  case let .processingFailed(processor, context, error) = error else {
                return XCTFail()
            }
            
            XCTAssertTrue(processor is MockFailingProcessor)
            
            XCTAssertEqual(context.request.url, Test.url)
            XCTAssertEqual(context.response.container.image.sizeInPixels, CGSize(width: 640, height: 480))
            XCTAssertEqual(context.response.cacheType, nil)
            XCTAssertEqual(context.isCompleted, true)
            
            XCTAssertEqual(error as? ImageProcessingError, .unknown)
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
        XCTAssertFalse(ImagePipeline.Error.dataLoadingFailed(error: URLError(.unknown)).description.isEmpty) // Just padding here
        
        XCTAssertFalse(ImagePipeline.Error.decodingFailed(decoder: MockImageDecoder(name: "test"), context: .mock, error: MockError(description: "decoding-failed")).description.isEmpty) // Just padding
        
        let processor = ImageProcessors.Resize(width: 100, unit: .pixels)
        let error = ImagePipeline.Error.processingFailed(processor: processor, context: .mock, error: MockError(description: "processing-failed"))
        let expected = "Failed to process the image using processor Resize(size: (100.0, 9999.0) pixels, contentMode: .aspectFit, crop: false, upscale: false). Underlying error: MockError(description: \"processing-failed\")."
        XCTAssertEqual(error.description, expected)
        XCTAssertEqual("\(error)", expected)
        
        XCTAssertNil(error.dataLoadingError)
    }
    
    // MARK: Skip Data Loading Queue Option
    
    func testSkipDataLoadingQueuePerRequestWithURL() throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        
        let request = ImageRequest(url: Test.url, options: [
            .skipDataLoadingQueue
        ])
        
        // Then image is still loaded
        expect(pipeline).toLoadImage(with: request)
        wait()
    }
    
    func testSkipDataLoadingQueuePerRequestWithPublisher() throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        
        let request = ImageRequest(id: "a", dataPublisher: Just(Test.data), options: [
            .skipDataLoadingQueue
        ])
        
        // Then image is still loaded
        expect(pipeline).toLoadImage(with: request)
        wait()
    }
    
    // MARK: Misc
    
    func testLoadWithStringLiteral() async throws {
        let image = try await pipeline.image(for: "https://example.com/image.jpeg")
        XCTAssertNotEqual(image.size, .zero)
    }

    func testLoadWithInvalidURL() throws {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataLoader = DataLoader()
        }
        
        // WHEN
        for _ in 0...100 {
            expect(pipeline).toFailRequest(ImageRequest(url: URL(string: "http://example.com/invalid url")))
            wait()
        }
    }
    
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
