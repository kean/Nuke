// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

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
            .progress(.init(completed: 22789, total: 22789)),
            .finished(try XCTUnwrap(result))
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
            .progress(.init(completed: 10, total: 20)),
            .progress(.init(completed: 20, total: 20)),
            .finished(try XCTUnwrap(result))
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
            .cancelled
        ])
    }
}
