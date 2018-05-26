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
        expect { fulfill in
            pipeline.didFinishCollectingMetrics = { task, metrics in
                XCTAssertEqual(task.taskId, metrics.taskId)
                XCTAssertNotNil(metrics.endDate)
                XCTAssertNotNil(metrics.session)
                XCTAssertNotNil(metrics.session?.endDate)
                fulfill()
            }
        }

        expect { fulfill in
            pipeline.loadImage(with: defaultURL) { response, _ in
                XCTAssertNotNil(response)
                fulfill()
            }
        }
        wait()
    }

    func testThatMetricsAreCollectedWhenTaskCancelled() {
        expect { fulfill in
            pipeline.didFinishCollectingMetrics = { task, metrics in
                XCTAssertEqual(task.taskId, metrics.taskId)
                XCTAssertTrue(metrics.wasCancelled)
                XCTAssertNotNil(metrics.endDate)
                XCTAssertNotNil(metrics.session)
                XCTAssertNotNil(metrics.session?.endDate)
                fulfill()
            }
        }

        dataLoader.queue.isSuspended = true

        let task = pipeline.loadImage(with: defaultURL) { _,_ in
            XCTFail()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
            task.cancel()
        }
        wait()
    }
}

