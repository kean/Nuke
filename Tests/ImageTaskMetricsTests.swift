// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageTaskMetricsTests: XCTestCase {
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

    func testThatMetricsAreCollectedWhenTaskCompleted() {
        let expectation = self.expectation(description: "Metrics Produced")
        pipeline.didFinishCollectingMetrics = { task, metrics in
            XCTAssertEqual(task.taskId, metrics.taskId)
            XCTAssertNotNil(metrics.endDate)
            XCTAssertNotNil(metrics.session)
            expectation.fulfill()
        }

        expect(pipeline).toLoadImage(with: Test.request)
        wait()
    }

    func testThatMetricsAreCollectedWhenTaskCancelled() {
        let expectation = self.expectation(description: "Metrics Produced")
        pipeline.didFinishCollectingMetrics = { task, metrics in
            XCTAssertEqual(task.taskId, metrics.taskId)
            XCTAssertTrue(metrics.wasCancelled)
            XCTAssertNotNil(metrics.endDate)
            XCTAssertNotNil(metrics.session)
            expectation.fulfill()
        }

        dataLoader.queue.isSuspended = true

        let task = pipeline.loadImage(with: Test.request) { _, _ in
            XCTFail()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
            task.cancel()
        }
        wait()
    }

    func testThatMetricsAreCollectedWhenTaskCompletedWithImageFromMemoryCache() {
        // Given
        let cache = MockImageCache()
        cache[Test.request] = Test.image

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
        }

        // When/Then
        let expectation = self.expectation(description: "Metrics Produced")
        pipeline.didFinishCollectingMetrics = { task, metrics in
            XCTAssertEqual(task.taskId, metrics.taskId)
            XCTAssertTrue(metrics.isMemoryCacheHit)
            XCTAssertNotNil(metrics.endDate)
            XCTAssertNil(metrics.session)
            expectation.fulfill()
        }

        expect(pipeline).toLoadImage(with: Test.request)
        wait()
    }
}
