// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke
@testable import NukeExtensions

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@MainActor
class ImageViewLoadingOptionsTests: XCTestCase {
    var mockCache: MockImageCache!
    var dataLoader: MockDataLoader!
    var imageView: _ImageView!
    
    @MainActor
    override func setUp() {
        super.setUp()
        
        mockCache = MockImageCache()
        dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = mockCache
        }
        // Nuke.loadImage(...) methods use shared pipeline by default.
        ImagePipeline.pushShared(pipeline)
        
        imageView = _ImageView()
    }
    
    override func tearDown() {
        super.tearDown()
        
        ImagePipeline.popShared()
    }
    
    // MARK: - Transition
    
    func testCustomTransitionPerformed() {
        // Given
        var options = ImageLoadingOptions()
        
        let expectTransition = self.expectation(description: "")
        options.transition = .custom({ (view, image) in
            // Then
            XCTAssertEqual(view, self.imageView)
            XCTAssertNil(self.imageView.image) // Image isn't displayed automatically.
            XCTAssertEqual(view, self.imageView)
            self.imageView.image = image
            expectTransition.fulfill()
        })
        
        // When
        expectToLoadImage(with: Test.request, options: options, into: imageView)
        wait()
    }
    
    // Tests https://github.com/kean/Nuke/issues/206
    func testImageIsDisplayedFadeInTransition() {
        // Given options with .fadeIn transition
        let options = ImageLoadingOptions(transition: .fadeIn(duration: 10))
        
        // When loading an image into an image view
        expectToLoadImage(with: Test.request, options: options, into: imageView)
        wait()
        
        // Then image is actually displayed
        XCTAssertNotNil(imageView.image)
    }
    
    // MARK: - Placeholder
    
    func testPlaceholderDisplayed() {
        // Given
        var options = ImageLoadingOptions()
        let placeholder = PlatformImage()
        options.placeholder = placeholder
        
        // When
        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView)
        
        // Then
        XCTAssertEqual(imageView.image, placeholder)
    }
    
    // MARK: - Failure Image
    
    func testFailureImageDisplayed() {
        // Given
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "ErrorDomain", code: 42, userInfo: nil)
        )
        
        var options = ImageLoadingOptions()
        let failureImage = PlatformImage()
        options.failureImage = failureImage
        
        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        wait()
        
        // Then
        XCTAssertEqual(imageView.image, failureImage)
    }
    
    func testFailureImageTransitionRun() {
        // Given
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )
        
        var options = ImageLoadingOptions()
        let failureImage = PlatformImage()
        options.failureImage = failureImage
        
        // Given
        let expectTransition = self.expectation(description: "")
        options.failureImageTransition = .custom({ (view, image) in
            // Then
            XCTAssertEqual(view, self.imageView)
            XCTAssertEqual(image, failureImage)
            self.imageView.image = image
            expectTransition.fulfill()
        })
        
        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        wait()
        
        // Then
        XCTAssertEqual(imageView.image, failureImage)
    }
    
#if !os(macOS)
    
    // MARK: - Content Modes
    
    func testPlaceholderAndSuccessContentModesApplied() {
        // Given
        var options = ImageLoadingOptions()
        options.contentModes = .init(
            success: .scaleAspectFill, // default is .scaleToFill
            failure: .center,
            placeholder: .center
        )
        options.placeholder = PlatformImage()
        
        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        
        // Then
        XCTAssertEqual(imageView.contentMode, .center)
        wait()
        XCTAssertEqual(imageView.contentMode, .scaleAspectFill)
    }
    
    func testSuccessContentModeAppliedWhenFromMemoryCache() {
        // Given
        var options = ImageLoadingOptions()
        options.contentModes = ImageLoadingOptions.ContentModes(
            success: .scaleAspectFill,
            failure: .center,
            placeholder: .center
        )
        
        mockCache[Test.request] = Test.container
        
        // When
        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView)
        
        // Then
        XCTAssertEqual(imageView.contentMode, .scaleAspectFill)
    }
    
    func testFailureContentModeApplied() {
        // Given
        var options = ImageLoadingOptions()
        options.contentModes = ImageLoadingOptions.ContentModes(
            success: .scaleAspectFill,
            failure: .center,
            placeholder: .center
        )
        options.failureImage = PlatformImage()
        
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )
        
        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        wait()
        
        // Then
        XCTAssertEqual(imageView.contentMode, .center)
    }
    
#endif
    
#if os(iOS) || os(tvOS) || os(visionOS)
    
    // MARK: - Tint Colors
    
    func testPlaceholderAndSuccessTintColorApplied() {
        // Given
        var options = ImageLoadingOptions()
        options.tintColors = .init(
            success: .blue,
            failure: nil,
            placeholder: .yellow
        )
        options.placeholder = PlatformImage()
        
        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        
        // Then
        XCTAssertEqual(imageView.tintColor, .yellow)
        wait()
        XCTAssertEqual(imageView.tintColor, .blue)
        XCTAssertEqual(imageView.image?.renderingMode, .alwaysTemplate)
    }
    
    func testSuccessTintColorAppliedWhenFromMemoryCache() {
        // Given
        var options = ImageLoadingOptions()
        options.tintColors = .init(
            success: .blue,
            failure: nil,
            placeholder: nil
        )
        
        mockCache[Test.request] = Test.container
        
        // When
        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView)
        
        // Then
        XCTAssertEqual(imageView.tintColor, .blue)
        XCTAssertEqual(imageView.image?.renderingMode, .alwaysTemplate)
    }
    
    func testFailureTintColorApplied() {
        // Given
        var options = ImageLoadingOptions()
        options.tintColors = .init(
            success: nil,
            failure: .red,
            placeholder: nil
        )
        options.failureImage = PlatformImage()
        
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )
        
        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        wait()
        
        // Then
        XCTAssertEqual(imageView.tintColor, .red)
        XCTAssertEqual(imageView.image?.renderingMode, .alwaysTemplate)
    }
    
#endif
    
    // MARK: - Pipeline
    
    func testCustomPipelineUsed() {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        
        var options = ImageLoadingOptions()
        options.pipeline = pipeline
        
        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        
        // Then
        wait { _ in
            _ = pipeline
            XCTAssertEqual(dataLoader.createdTaskCount, 1)
            XCTAssertEqual(self.dataLoader.createdTaskCount, 0)
        }
    }
    
    // MARK: - Shared Options
    
    func testSharedOptionsUsed() {
        // Given
        var options = ImageLoadingOptions.shared
        let placeholder = PlatformImage()
        options.placeholder = placeholder
        
        ImageLoadingOptions.pushShared(options)
        
        // When
        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView)
        
        // Then
        XCTAssertEqual(imageView.image, placeholder)
        
        ImageLoadingOptions.popShared()
    }
    
    // MARK: - Cache Policy
    
    func testReloadIgnoringCachedData() {
        // When the requested image is stored in memory cache
        var request = Test.request
        mockCache[request] = ImageContainer(image: PlatformImage())
        
        request.options = [.reloadIgnoringCachedData]
        
        // When
        expectToFinishLoadingImage(with: request, into: imageView)
        wait()
        
        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
    }
    
    // MARK: - Misc
    
#if os(iOS) || os(tvOS) || os(visionOS)
    func testTransitionCrossDissolve() {
        // GIVEN
        var options = ImageLoadingOptions()
        options.placeholder = Test.image
        options.transition = .fadeIn(duration: 0.33)
        options.isPrepareForReuseEnabled = false
        options.contentModes = .init(
            success: .scaleAspectFill,
            failure: .center,
            placeholder: .center
        )
        
        imageView.image = Test.image
        
        // WHEN
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        wait()
        
        // THEN make sure we run the pass with cross-disolve and at least
        // it doesn't crash
    }
#endif
    
    func testSettingDefaultProcessor() {
        // GIVEN
        var options = ImageLoadingOptions()
        options.processors = [MockImageProcessor(id: "p1")]
        
        // WHEN
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        wait()
        
        // THEN
        XCTAssertEqual(imageView.image?.nk_test_processorIDs, ["p1"])
    }
}

#endif
