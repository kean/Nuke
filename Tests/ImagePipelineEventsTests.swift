// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineObservingTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    private var observer: MockImagePipelineObserver!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        observer = MockImagePipelineObserver()
        pipeline.observer = observer
    }

    // MARK: - Completion

    func testStartAndCompletedEvents() throws {
        var result: Result<ImageResponse, ImagePipeline.Error>?
        expect(pipeline).toLoadImage(with: Test.request) { result = $0 }
        wait()

        // Then
        XCTAssertEqual(observer.events, [
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
        XCTAssertEqual(observer.events, [
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

        let task = pipeline.loadImage(with: request)
        wait() // Wait till the operation is created.

        guard let operation = operationQueueObserver.operations.first else {
            return XCTFail("Failed to find operation")
        }
        expect(operation).toUpdatePriority()
        task.priority = .high
        wait()

        // Then
        XCTAssertEqual(observer.events, [
            ImageTaskEvent.started,
            .priorityUpdated(priority: .high)
        ])
    }

    func testCancelationEvents() {
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
        XCTAssertEqual(observer.events, [
            ImageTaskEvent.started,
            .cancelled
        ])
    }
}

private final class MockImagePipelineObserver: ImagePipelineObserving {
    var events = [ImageTaskEvent]()

    func pipeline(_ pipeline: ImagePipeline, imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent) {
        events.append(event)
    }
}
