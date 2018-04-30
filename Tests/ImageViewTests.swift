// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageViewTests: XCTestCase {
    var mockCache: MockImageCache!
    var mockDataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    var imageView: ImageView!

    override func setUp() {
        super.setUp()

        mockCache = MockImageCache()
        mockDataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = mockDataLoader
            $0.imageCache = mockCache
        }

        imageView = ImageView()
        imageView.options.pipeline = pipeline
    }

    // MARK: - Prepare For Reuse

    func testThatImageIsPreparedForReuse() {
        imageView.image = Test.image
        Nuke.loadImage(with: Test.request, into: imageView)
        XCTAssertNil(imageView.image)
    }

    func testThatPrepareForReuseCanBeDisabled() {
        imageView.options.isPrepareForReuseEnabled = false
        imageView.image = Test.image
        Nuke.loadImage(with: Test.request, into: imageView)
        XCTAssertEqual(imageView.image, Test.image)
    }

    // MARK: - Memory Cache

    func testThatImageIsReadSyncrhonouslyFromMemoryCache() {
        mockCache[Test.request] = Test.image

        XCTAssertNil(imageView.image)
        Nuke.loadImage(with: Test.request, into: imageView)

        XCTAssertEqual(imageView.image, Test.image)
    }

    func testThatReadAllowedFalseDisabledMemoryCacheLookup() {
        mockCache[Test.request] = Test.image

        XCTAssertNil(imageView.image)
        var request = Test.request
        request.memoryCacheOptions.readAllowed = false

        Nuke.loadImage(with: request, into: imageView)

        XCTAssertNil(imageView.image) // Image will load asynchronously
    }

    func testThatCompletionIsCalledWhenImageIsReturnedFromMemoryCache() {
        mockCache[Test.request] = Test.image

        var didCallCompletion = false
        Nuke.loadImage(
            with: Test.request,
            into: imageView,
            completion: { response, _, isFromMemoryCache in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertNotNil(response)
                XCTAssertTrue(isFromMemoryCache)
                didCallCompletion = true
        })

        XCTAssertTrue(didCallCompletion)
    }

    func testThatCompletionIsCalledWhenImageIsLoadedAsynchronously() {
        var didCallCompletion = false

        expect { fulfil in
            Nuke.loadImage(
                with: Test.request,
                into: imageView,
                completion: { response, _, isFromMemoryCache in
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertNotNil(response)
                    XCTAssertFalse(isFromMemoryCache)
                    didCallCompletion = true
                    fulfil()
            })
        }

        XCTAssertFalse(didCallCompletion)
        wait()
    }

    // MARK: - Transition

    func testThatCustomTransitioIsPerformed() {
        let expectTransition = self.expectation(description: "")
        imageView.options.transition = .custom({ (view, image, _) in
            XCTAssertNil(view.image) // Image isn't displayed automatically.
            XCTAssertEqual(view, self.imageView)
            view.image = image
            expectTransition.fulfill()
        })

        let expectCompletion = self.expectation(description: "")
        Nuke.loadImage(
            with: Test.request,
            into: imageView,
            completion: { _, _, _ in
                expectCompletion.fulfill()
        })

        wait()
    }

    // MARK: - Placeholder

    func testThatPlaceholderIsDisplayed() {
        let placeholder = Image()
        imageView.options.placeholder = placeholder

        XCTAssertNil(imageView.image)
        Nuke.loadImage(with: Test.request, into: imageView)
        XCTAssertEqual(imageView.image, placeholder)
    }

    // MARK: - Failure Image

    func testThatFailureImageIsDisplayed() {
        mockDataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )

        let failureImage = Image()
        imageView.options.failureImage = failureImage

        expect { fulfil in
            Nuke.loadImage(
                with: Test.request,
                into: imageView,
                completion: { response, error, isFromMemoryCache in
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertNotNil(error)
                    XCTAssertNil(response)
                    XCTAssertFalse(isFromMemoryCache)
                    fulfil()
            })
        }
        wait()

        XCTAssertEqual(imageView.image, failureImage)
    }

    func testThatFailureImageTransitionIsUsed() {
        mockDataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )

        let failureImage = Image()
        imageView.options.failureImage = failureImage

        let expectTransition = self.expectation(description: "")
        imageView.options.failureImageTransition = .custom({ (view, image, _) in
            XCTAssertEqual(view, self.imageView)
            XCTAssertEqual(image, failureImage)
            view.image = image
            expectTransition.fulfill()
        })

        let expectCompletion = self.expectation(description: "")
        Nuke.loadImage(
            with: Test.request,
            into: imageView,
            completion: { _, _, _ in
                expectCompletion.fulfill()
        })
        
        wait()

        XCTAssertEqual(imageView.image, failureImage)
    }

    #if !os(macOS)

    // MARK: - Content Modes

    func testThatPlaceholderAndSuccessContentModeIsApplied() {
        imageView.options.contentModes = ImageViewOptions.ContentModes(
            success: .scaleAspectFill, // default is .scaleToFill
            placeholder: .center
        )
        imageView.options.placeholder = Image()

        let expectCompletion = self.expectation(description: "")
        Nuke.loadImage(
            with: Test.request,
            into: imageView,
            completion: { _, _, _ in
                expectCompletion.fulfill()
        })

        XCTAssertEqual(imageView.contentMode, .center)

        wait()

        XCTAssertEqual(imageView.contentMode, .scaleAspectFill)
    }

    func testThatSuccessContentModeIsAppliedWhenReturnedFromMemoryCache() {
        imageView.options.contentModes = ImageViewOptions.ContentModes(
            success: .scaleAspectFill
        )

        mockCache[Test.request] = Test.image
        Nuke.loadImage(with: Test.request, into: imageView)

        XCTAssertEqual(imageView.contentMode, .scaleAspectFill)
    }

    func testThatFailureContentModeIsApplied() {
        imageView.options.contentModes = ImageViewOptions.ContentModes(
            failure: .center // default is .scaleToFill
        )
        imageView.options.failureImage = Image()

        mockDataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )
        let expectCompletion = self.expectation(description: "")
        Nuke.loadImage(
            with: Test.request,
            into: imageView,
            completion: { _, _, _ in
                expectCompletion.fulfill()
        })

        wait()

        XCTAssertEqual(imageView.contentMode, .center)
    }

    #endif
}

class ImageViewTaskManagementTests: XCTestCase {
    var pipeline: MockImagePipeline!
    var imageView: ImageView!

    override func setUp() {
        super.setUp()

        pipeline = MockImagePipeline()

        imageView = ImageView()
        imageView.options.pipeline = pipeline
    }

    // MARK: - Managing Tasks

    func testThatTaskIsReturned() {
        let task = Nuke.loadImage(with: Test.request, into: imageView)
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.request.urlRequest, Test.request.urlRequest)
    }

    func testThatFirstTaskNoLongerObserved() {
        let url1 = defaultURL.appendingPathComponent("01")
        let url2 = defaultURL.appendingPathComponent("02")

        pipeline.perform = { task in
            if task.request.urlRequest.url == url1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
                    task.completion?(Test.response, nil)
                }
            }
            if task.request.urlRequest.url == url2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                    task.completion?(Test.response, nil)
                }
            }
        }

        Nuke.loadImage(
            with: url1,
            into: imageView,
            completion: { _, _, _ in
                XCTFail() // The first requests is ignored
        })

        expect { fulfil in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                Nuke.loadImage(
                    with: url2,
                    into: self.imageView,
                    completion: { response, _, isFromMemoryCache in
                        XCTAssertNotNil(response)
                        fulfil()
                })
            }
        }

        wait()
    }

    // MARK: - Cancellation

    func testThatOutstandingRequestIsCancelledAutomatically() {
        pipeline.queue.isSuspended = true

        Nuke.loadImage(with: defaultURL, into: imageView)
        _ = expectNotification(MockImagePipeline.DidCancelTask, object: pipeline)
        Nuke.cancelRequest(for: imageView)

        wait()
    }

    func testThatOutstandingRequestIsCancelledWhenNewRequestStarted() {
        pipeline.queue.isSuspended = true

        Nuke.loadImage(with: defaultURL, into: imageView)
        _ = expectNotification(MockImagePipeline.DidCancelTask, object: pipeline)
        Nuke.loadImage(with: defaultURL, into: imageView)

        wait()
    }

    func testThatRequestIsCancelledWhenTargetIsDeallocated() {
        // Wrap everything in autorelease pool to make sure that imageView
        // gets deallocated immediately.
        autoreleasepool {
            var imageView: ImageView! = ImageView()
            imageView.options.pipeline = pipeline

            pipeline.queue.isSuspended = true

            Nuke.loadImage(with: defaultURL, into: imageView)

            _ = expectNotification(MockImagePipeline.DidCancelTask, object: pipeline)

            imageView = nil // deallocate target
        }
        wait()
    }
}
