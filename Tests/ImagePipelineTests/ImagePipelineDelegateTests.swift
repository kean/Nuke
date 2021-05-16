//// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineDelegateTests: XCTestCase {
    private var dataLoader: MockDataLoader!
    private var dataCache: MockDataCache!
    private var pipeline: ImagePipeline!
    private var delegate: MockImagePipelineDelegate!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        dataCache = MockDataCache()
        delegate = MockImagePipelineDelegate()

        pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.dataCachePolicy = .automatic
            $0.imageCache = nil
            $0.debugIsSyncImageEncoding = true
        }
    }

    func testCustomizingDataCacheKey() throws {
        // GIVEN
        let imageURLSmall = URL(string: "https://example.com/image-01-small.jpeg")!
        let imageURLMedium = URL(string: "https://example.com/image-01-medium.jpeg")!

        dataLoader.results[imageURLMedium] = .success(
            (Test.data, URLResponse(url: imageURLMedium, mimeType: "jpeg", expectedContentLength: Test.data.count, textEncodingName: nil))
        )

        // GIVEN image is loaded from medium size URL and saved in cache using imageId "image-01-small"
        let requestA = ImageRequest(
            url: imageURLMedium,
            processors: [ImageProcessors.Resize(width: 44)],
            options: .init(userInfo: ["imageId": "image-01-small"])
        )
        expect(pipeline).toLoadImage(with: requestA)
        wait()

        let data = try XCTUnwrap(dataCache.cachedData(for: "image-01-small"))
        let image = try XCTUnwrap(PlatformImage(data: data))
        XCTAssertEqual(image.sizeInPixels.width, 44 * Screen.scale)

        // GIVEN a request for a small image
        let requestB = ImageRequest(
            url: imageURLSmall,
            options: .init(userInfo: ["imageId": "image-01-small"])
        )

        // WHEN/THEN the image is returned from the disk cache
        expect(pipeline).toLoadImage(with: requestB, completion: { result in
            guard let image = result.value?.image else {
                return XCTFail()
            }
            XCTAssertEqual(image.sizeInPixels.width, 44 * Screen.scale)
        })
        wait()
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
    }

    // MARK: Monitoring

    func testStartAndCompletedEvents() throws {
        var result: Result<ImageResponse, ImagePipeline.Error>?
        expect(pipeline).toLoadImage(with: Test.request) { result = $0 }
        wait()

        // Then
        XCTAssertEqual(delegate.events, [
            ImageTaskEvent.started,
            .progressUpdated(completedUnitCount: 22789, totalUnitCount: -1),
            .completed(result: try XCTUnwrap(result))
        ])
    }

    func testProgressUpdateEvents() throws {
        let request = ImageRequest(url: Test.url)
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        var result: Result<ImageResponse, ImagePipeline.Error>?
        expect(pipeline).toFailRequest(request) { result = $0 }
        wait()

        // Then
        XCTAssertEqual(delegate.events, [
            ImageTaskEvent.started,
            .progressUpdated(completedUnitCount: 10, totalUnitCount: 20),
            .progressUpdated(completedUnitCount: 20, totalUnitCount: 20),
            .completed(result: try XCTUnwrap(result))
        ])
    }

    func testUpdatePriorityEvents() {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = Test.request
        XCTAssertEqual(request.priority, .normal)

        let operationQueueObserver = self.expect(queue).toEnqueueOperationsWithCount(1)

        let task = pipeline.loadImage(with: request) { _ in }
        wait() // Wait till the operation is created.

        guard let operation = operationQueueObserver.operations.first else {
            return XCTFail("Failed to find operation")
        }
        expect(operation).toUpdatePriority()
        task.priority = .high
        wait()

        // Then
        XCTAssertEqual(delegate.events, [
            ImageTaskEvent.started,
            .priorityUpdated(priority: .high)
        ])
    }

    func testCancellationEvents() {
        dataLoader.queue.isSuspended = true

        expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.loadImage(with: Test.request) { _ in
            XCTFail()
        }
        wait() // Wait till operation is created

        expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
        task.cancel()
        wait()

        // Then
        XCTAssertEqual(delegate.events, [
            ImageTaskEvent.started,
            .cancelled
        ])
    }
}

private final class MockImagePipelineDelegate: ImagePipelineDelegate {
    func pipeline(_ pipeline: ImagePipeline, cacheKeyFor request: ImageRequest) -> ImagePipeline.CacheKey<String> {
        guard let imageId = request.options.userInfo["imageId"] as? String else {
            return .default
        }
        return .custom(key: imageId)
    }

    var events = [ImageTaskEvent]()

    func pipeline(_ pipeline: ImagePipeline, imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent) {
        events.append(event)
    }
}
