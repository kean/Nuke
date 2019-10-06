// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineConfigurationTests: XCTestCase {

    func testImageIsLoadedWithRateLimiterDisabled() {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil

            $0.isRateLimiterEnabled = false
        }

        // When/Then
        expect(pipeline).toLoadImage(with: Test.request)
        wait()
    }

    // MARK: Changing Callback Queue

    func testChangingCallbackQueueLoadImage() {
        // Given
        let queue = DispatchQueue(label: "testChangingCallbackQueue")
        let queueKey = DispatchSpecificKey<Void>()
        queue.setSpecific(key: queueKey, value: ())

        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil

            $0.callbackQueue = queue
        }

        // When/Then
        let expectation = self.expectation(description: "Image Loaded")
        pipeline.loadImage(with: Test.url, progress: { _, _, _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
        }, completion: { _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
            expectation.fulfill()
        })
        wait()
    }

    func testChangingCallbackQueueLoadData() {
        // Given
        let queue = DispatchQueue(label: "testChangingCallbackQueue")
        let queueKey = DispatchSpecificKey<Void>()
        queue.setSpecific(key: queueKey, value: ())

        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil

            $0.callbackQueue = queue
        }

        // When/Then
        let expectation = self.expectation(description: "Image data Loaded")
        pipeline.loadData(with: Test.request, progress: { _, _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
        }, completion: { _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
            expectation.fulfill()
        })
        wait()
    }
}   
