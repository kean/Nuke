// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageViewTests: XCTestCase {
    var mockCache: MockImageCache!
    var dataLoader: MockDataLoader!
    var _sharedPipeline: ImagePipeline!
    var pipeline: ImagePipeline!
    var imageView: _ImageView!

    override func setUp() {
        super.setUp()

        mockCache = MockImageCache()
        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = mockCache
        }

        imageView = _ImageView()

        _sharedPipeline = ImagePipeline.shared
        ImagePipeline.shared = pipeline
    }

    override func tearDown() {
        ImagePipeline.shared = _sharedPipeline
    }

    // MARK: - Managing Tasks

    func testThatTaskIsReturned() {
        let task = Nuke.loadImage(with: Test.request, into: imageView)
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.request.urlRequest, Test.request.urlRequest)
    }

    // MARK: - Prepare For Reuse

    func testThatImageIsPreparedForReuse() {
        imageView.image = Test.image
        Nuke.loadImage(with: Test.request, into: imageView)
        XCTAssertNil(imageView.image)
    }

    func testThatPrepareForReuseCanBeDisabled() {
        var options = ImageLoadingOptions()
        options.isPrepareForReuseEnabled = false

        imageView.image = Test.image
        Nuke.loadImage(with: Test.request, options: options, into: imageView)
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
        request.memoryCacheOptions.isReadAllowed = false

        Nuke.loadImage(with: request, into: imageView)

        XCTAssertNil(imageView.image) // Image will load asynchronously
    }

    // MARK: - Completion and Progress Closurres

    func testThatCompletionIsCalledWhenImageIsReturnedFromMemoryCache() {
        mockCache[Test.request] = Test.image

        var didCallCompletion = false
        Nuke.loadImage(
            with: Test.request,
            into: imageView,
            completion: { response, _ in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertNotNil(response)
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
                completion: { response, _ in
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertNotNil(response)
                    didCallCompletion = true
                    fulfil()
            })
        }

        XCTAssertFalse(didCallCompletion)
        wait()
    }

    func testThatProgressHandlerIsCalled() {
        dataLoader.results[defaultURL] = .success(
            (Data(count: 20), URLResponse(url: defaultURL, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        let expectTaskFinished = self.expectation(description: "Task finished")
        let expectProgressFinished = self.expectation(description: "Progress finished")

        var expected: [(Int64, Int64)] = [(10, 20), (20, 20)]
        Nuke.loadImage(
            with: Test.request,
            into: imageView,
            progress: { _, completed, total in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertTrue(expected.first?.0 == completed)
                XCTAssertTrue(expected.first?.1 == total)
                expected.remove(at: 0)
                if expected.isEmpty {
                    expectProgressFinished.fulfill()
                }
            },
            completion: { _,_ in
                expectTaskFinished.fulfill()
        })

        wait()
    }

    // MARK: - Transition

    func testThatCustomTransitioIsPerformed() {
        var options = ImageLoadingOptions()

        let expectTransition = self.expectation(description: "")
        options.transition = .custom({ (view, image) in
            XCTAssertEqual(view, self.imageView)
            XCTAssertNil(self.imageView.image) // Image isn't displayed automatically.
            XCTAssertEqual(view, self.imageView)
            self.imageView.image = image
            expectTransition.fulfill()
        })

        let expectCompletion = self.expectation(description: "")
        Nuke.loadImage(
            with: Test.request,
            options: options,
            into: imageView,
            completion: { _, _ in
                expectCompletion.fulfill()
        })

        wait()
    }

    // MARK: - Placeholder

    func testThatPlaceholderIsDisplayed() {
        var options = ImageLoadingOptions()

        let placeholder = Image()
        options.placeholder = placeholder

        XCTAssertNil(imageView.image)
        Nuke.loadImage(with: Test.request, options: options, into: imageView)
        XCTAssertEqual(imageView.image, placeholder)
    }

    // MARK: - Failure Image

    func testThatFailureImageIsDisplayed() {
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )


        var options = ImageLoadingOptions()
        let failureImage = Image()
        options.failureImage = failureImage

        expect { fulfil in
            Nuke.loadImage(
                with: Test.request,
                options: options,
                into: imageView,
                completion: { response, error in
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertNotNil(error)
                    XCTAssertNil(response)
                    fulfil()
            })
        }
        wait()

        XCTAssertEqual(imageView.image, failureImage)
    }

    func testThatFailureImageTransitionIsUsed() {
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )

        var options = ImageLoadingOptions()
        let failureImage = Image()
        options.failureImage = failureImage

        let expectTransition = self.expectation(description: "")
        options.failureImageTransition = .custom({ (view, image) in
            XCTAssertEqual(view, self.imageView)
            XCTAssertEqual(image, failureImage)
            self.imageView.image = image
            expectTransition.fulfill()
        })

        let expectCompletion = self.expectation(description: "")
        Nuke.loadImage(
            with: Test.request,
            options: options,
            into: imageView,
            completion: { _, _ in
                expectCompletion.fulfill()
        })
        
        wait()

        XCTAssertEqual(imageView.image, failureImage)
    }

    #if !os(macOS)

    // MARK: - Content Modes

    func testThatPlaceholderAndSuccessContentModeIsApplied() {
        var options = ImageLoadingOptions()
        options.contentModes = .init(
            success: .scaleAspectFill, // default is .scaleToFill
            failure: .center,
            placeholder: .center
        )
        options.placeholder = Image()

        let expectCompletion = self.expectation(description: "")
        Nuke.loadImage(
            with: Test.request,
            options: options,
            into: imageView,
            completion: { _, _ in
                expectCompletion.fulfill()
        })

        XCTAssertEqual(imageView.contentMode, .center)

        wait()

        XCTAssertEqual(imageView.contentMode, .scaleAspectFill)
    }

    func testThatSuccessContentModeIsAppliedWhenReturnedFromMemoryCache() {
        var options = ImageLoadingOptions()
        options.contentModes = ImageLoadingOptions.ContentModes(
            success: .scaleAspectFill,
            failure: .center,
            placeholder: .center
        )

        mockCache[Test.request] = Test.image
        Nuke.loadImage(with: Test.request, options: options, into: imageView)

        XCTAssertEqual(imageView.contentMode, .scaleAspectFill)
    }

    func testThatFailureContentModeIsApplied() {
        var options = ImageLoadingOptions()
        options.contentModes = ImageLoadingOptions.ContentModes(
            success: .scaleAspectFill,
            failure: .center,
            placeholder: .center
        )
        options.failureImage = Image()

        dataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )
        let expectCompletion = self.expectation(description: "")
        Nuke.loadImage(
            with: Test.request,
            options: options,
            into: imageView,
            completion: { _, _ in
                expectCompletion.fulfill()
        })

        wait()

        XCTAssertEqual(imageView.contentMode, .center)
    }

    #endif

    // MARK: - Cancellation

    func testThatOutstandingRequestIsCancelledAutomatically() {
        dataLoader.queue.isSuspended = true

        _ = expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        Nuke.loadImage(with: Test.url, into: imageView)
        wait()

        _ = expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
        Nuke.cancelRequest(for: imageView)

        wait()
    }

    func testThatOutstandingRequestIsCancelledWhenNewRequestStarted() {
        dataLoader.queue.isSuspended = true

        _ = expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        Nuke.loadImage(with: Test.url, into: imageView)
        wait()

        _ = expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
        Nuke.loadImage(with: Test.url, into: imageView)
        wait()
    }

    func testThatRequestIsCancelledWhenTargetIsDeallocated() {
        // Wrap everything in autorelease pool to make sure that imageView
        // gets deallocated immediately.
        autoreleasepool {
            var imageView: _ImageView! = _ImageView()

            dataLoader.queue.isSuspended = true

            _ = expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
            Nuke.loadImage(with: Test.url, into: imageView)
            wait()

            _ = expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)

            imageView = nil // deallocate target
        }
        wait()
    }
}
