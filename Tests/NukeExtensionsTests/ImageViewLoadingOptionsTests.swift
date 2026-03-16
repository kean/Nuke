// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeExtensions

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@Suite(.timeLimit(.minutes(2))) @MainActor
struct ImageViewLoadingOptionsTests {
    let mockCache: MockImageCache
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline
    let imageView: _ImageView
    let options: ImageLoadingOptions

    init() {
        let mockCache = MockImageCache()
        let dataLoader = MockDataLoader()
        self.mockCache = mockCache
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = mockCache
        }
        self.imageView = _ImageView()
        var options = ImageLoadingOptions()
        options.pipeline = pipeline
        self.options = options
    }

    // MARK: - Transition

    @Test func customTransitionPerformed() async {
        // Given
        var options = options

        let expectTransition = TestExpectation()
        options.transition = .custom({ (view, image) in
            // Then
            #expect(view == self.imageView)
            #expect(self.imageView.image == nil) // Image isn't displayed automatically.
            #expect(view == self.imageView)
            self.imageView.image = image
            expectTransition.fulfill()
        })

        // When
        await loadImageExpectingSuccess(with: Test.request, options: options, into: imageView)
        await expectTransition.wait()
    }

    // Tests https://github.com/kean/Nuke/issues/206
    @Test func imageIsDisplayedFadeInTransition() async {
        // Given options with .fadeIn transition
        var options = options
        options.transition = .fadeIn(duration: 10)

        // When loading an image into an image view
        await loadImageExpectingSuccess(with: Test.request, options: options, into: imageView)

        // Then image is actually displayed
        #expect(imageView.image != nil)
    }

    // MARK: - Placeholder

    @Test func placeholderDisplayed() {
        // Given
        var options = options
        let placeholder = PlatformImage()
        options.placeholder = placeholder

        // When
        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.image == placeholder)
    }

    // MARK: - Failure Image

    @Test func failureImageDisplayed() async {
        // Given
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "ErrorDomain", code: 42, userInfo: nil)
        )

        var options = options
        let failureImage = PlatformImage()
        options.failureImage = failureImage

        // When
        await loadImageAndWait(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.image == failureImage)
    }

    @Test func failureImageTransitionRun() async {
        // Given
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )

        var options = options
        let failureImage = PlatformImage()
        options.failureImage = failureImage

        // Given
        let expectTransition = TestExpectation()
        options.failureImageTransition = .custom({ (view, image) in
            // Then
            #expect(view == self.imageView)
            #expect(image == failureImage)
            self.imageView.image = image
            expectTransition.fulfill()
        })

        // When
        await loadImageAndWait(with: Test.request, options: options, into: imageView)
        await expectTransition.wait()

        // Then
        #expect(imageView.image == failureImage)
    }

#if !os(macOS)

    // MARK: - Content Modes

    @Test func placeholderAndSuccessContentModesApplied() async {
        // Given
        var options = options
        options.contentModes = .init(
            success: .scaleAspectFill, // default is .scaleToFill
            failure: .center,
            placeholder: .center
        )
        options.placeholder = PlatformImage()

        // When
        let expectation = TestExpectation()
        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView) { _ in
            expectation.fulfill()
        }

        // Then
        #expect(imageView.contentMode == .center)
        await expectation.wait()
        #expect(imageView.contentMode == .scaleAspectFill)
    }

    @Test func successContentModeAppliedWhenFromMemoryCache() {
        // Given
        var options = options
        options.contentModes = ImageLoadingOptions.ContentModes(
            success: .scaleAspectFill,
            failure: .center,
            placeholder: .center
        )

        mockCache[Test.request] = Test.container

        // When
        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.contentMode == .scaleAspectFill)
    }

    @Test func failureContentModeApplied() async {
        // Given
        var options = options
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
        await loadImageAndWait(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.contentMode == .center)
    }

#endif

#if os(iOS) || os(tvOS) || os(visionOS)

    // MARK: - Tint Colors

    @Test func placeholderAndSuccessTintColorApplied() async {
        // Given
        var options = options
        options.tintColors = .init(
            success: .blue,
            failure: nil,
            placeholder: .yellow
        )
        options.placeholder = PlatformImage()

        // When
        let expectation = TestExpectation()
        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView) { _ in
            expectation.fulfill()
        }

        // Then
        #expect(imageView.tintColor == .yellow)
        await expectation.wait()
        #expect(imageView.tintColor == .blue)
        #expect(imageView.image?.renderingMode == .alwaysTemplate)
    }

    @Test func successTintColorAppliedWhenFromMemoryCache() {
        // Given
        var options = options
        options.tintColors = .init(
            success: .blue,
            failure: nil,
            placeholder: nil
        )

        mockCache[Test.request] = Test.container

        // When
        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.tintColor == .blue)
        #expect(imageView.image?.renderingMode == .alwaysTemplate)
    }

    @Test func failureTintColorApplied() async {
        // Given
        var options = options
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
        await loadImageAndWait(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.tintColor == .red)
        #expect(imageView.image?.renderingMode == .alwaysTemplate)
    }

#endif

    // MARK: - Pipeline

    @Test func customPipelineUsed() async {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        var options = ImageLoadingOptions()
        options.pipeline = pipeline

        // When
        await loadImageAndWait(with: Test.request, options: options, into: imageView)

        // Then
        _ = pipeline
        #expect(dataLoader.createdTaskCount == 1)
        #expect(self.dataLoader.createdTaskCount == 0)
    }

    // MARK: - Shared Options

    @Test func sharedOptionsUsed() {
        // Given
        var options = options
        let placeholder = PlatformImage()
        options.placeholder = placeholder

        // When
        NukeExtensions.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.image == placeholder)
    }

    // MARK: - Cache Policy

    @Test func reloadIgnoringCachedData() async {
        // When the requested image is stored in memory cache
        var request = Test.request
        mockCache[request] = ImageContainer(image: PlatformImage())

        request.options = [.reloadIgnoringCachedData]

        // When
        await loadImageAndWait(with: request, options: options, into: imageView)

        // Then
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Misc

#if os(iOS) || os(tvOS) || os(visionOS)
    @Test func transitionCrossDissolve() async {
        // GIVEN
        var options = options
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
        await loadImageAndWait(with: Test.request, options: options, into: imageView)

        // THEN make sure we run the pass with cross-disolve and at least
        // it doesn't crash
    }
#endif

    @Test func settingDefaultProcessor() async {
        // GIVEN
        var options = options
        options.processors = [MockImageProcessor(id: "p1")]

        // WHEN
        await loadImageAndWait(with: Test.request, options: options, into: imageView)

        // THEN
        #expect(imageView.image?.nk_test_processorIDs == ["p1"])
    }
}

#endif
