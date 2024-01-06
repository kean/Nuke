// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineTaskDelegateTests: XCTestCase {
    private var dataLoader: MockDataLoader!
    private var pipeline: ImagePipeline!
    private var delegate: ImagePipelineObserver!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        delegate = ImagePipelineObserver()

        pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    func testStartAndCompletedEvents() throws {
        var result: Result<ImageResponse, ImagePipeline.Error>?
        expect(pipeline).toLoadImage(with: Test.request) { result = $0 }
        wait()

        // Then
        XCTAssertEqual(delegate.events, [
            ImageTaskEvent.created,
            .started,
            .progressUpdated(completedUnitCount: 22789, totalUnitCount: 22789),
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
            ImageTaskEvent.created,
            .started,
            .progressUpdated(completedUnitCount: 10, totalUnitCount: 20),
            .progressUpdated(completedUnitCount: 20, totalUnitCount: 20),
            .completed(result: try XCTUnwrap(result))
        ])
    }

    func testCancellationEvents() {
        dataLoader.queue.isSuspended = true

        expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.loadImage(with: Test.request) { _ in
            XCTFail()
        }
        wait() // Wait till operation is created

        expectNotification(ImagePipelineObserver.didCancelTask, object: delegate)
        task.cancel()
        wait()

        // Then
        XCTAssertEqual(delegate.events, [
            ImageTaskEvent.created,
            .started,
            .cancelled
        ])
    }
}
