// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation

@testable import Nuke
@testable import NukeExtensions

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@MainActor
@Suite class ImageViewLoadingOptionsTests {
    var mockCache: MockImageCache!
    var dataLoader: MockDataLoader!
    var imageView: _ImageView!
    var options = ImageLoadingOptions()

    init() {
        mockCache = MockImageCache()
        dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = mockCache
        }
        options.pipeline = pipeline

        imageView = _ImageView()
    }

    // MARK: - Transition

    @Test func customTransitionPerformed() async throws {
        // Given
        let expectTransition = AsyncExpectation<Void>()
        options.transition = .custom({ (view, image) in
            // Then
            #expect(view == self.imageView)
            #expect(self.imageView.image == nil) // Image isn't displayed automatically. // Image isn't displayed automatically.
            #expect(view == self.imageView)
            self.imageView.image = image
            expectTransition.fulfill()
        })

        // When
        try await loadImage(with: Test.request, options: options, into: imageView)
        await expectTransition.wait()
    }

    // Tests https://github.com/kean/Nuke/issues/206
    @Test func imageIsDisplayedFadeInTransition() async throws {
        // Given options with .fadeIn transition
        options.transition = .fadeIn(duration: 10)

        // When loading an image into an image view
        try await loadImage(with: Test.request, options: options, into: imageView)

        // Then image is actually displayed
        #expect(imageView.image != nil)
    }

    // MARK: - Placeholder

    @Test func placeholderDisplayed() {
        // Given
        let placeholder = PlatformImage()
        options.placeholder = placeholder

        // When
        loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.image == placeholder)
    }

    // MARK: - Failure Image

    @Test func failureImageDisplayed() async throws {
        // Given
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "ErrorDomain", code: 42, userInfo: nil)
        )

        let failureImage = PlatformImage()
        options.failureImage = failureImage

        // When
        try? await loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.image == failureImage)
    }

    @Test func failureImageTransitionRun() async throws {
        // Given
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )

        let failureImage = PlatformImage()
        options.failureImage = failureImage

        // Given
        let expectTransition = AsyncExpectation<Void>()
        options.failureImageTransition = .custom({ (view, image) in
            // Then
            #expect(view == self.imageView)
            #expect(image == failureImage)
            self.imageView.image = image
            expectTransition.fulfill()
        })

        // When
        try? await loadImage(with: Test.request, options: options, into: imageView)
        _ = await expectTransition.wait()

        // Then
        #expect(imageView.image == failureImage)
    }

#if !os(macOS)

    // MARK: - Content Modes

    @Test func placeholderAndSuccessContentModesApplied() async throws {
        // Given
        options.contentModes = .init(
            success: .scaleAspectFill, // default is .scaleToFill
            failure: .center,
            placeholder: .center
        )
        options.placeholder = PlatformImage()

        // When
        let expectation = AsyncExpectation<Void>()
        loadImage(with: Test.request, options: options, into: imageView) { _ in
            expectation.fulfill()
        }

        // Then
        #expect(imageView.contentMode == .center)
        await expectation.wait()
        #expect(imageView.contentMode == .scaleAspectFill)
    }

    @Test func successContentModeAppliedWhenFromMemoryCache() async throws {
        // Given
        options.contentModes = ImageLoadingOptions.ContentModes(
            success: .scaleAspectFill,
            failure: .center,
            placeholder: .center
        )

        mockCache[Test.request] = Test.container

        // When
        try await loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.contentMode == .scaleAspectFill)
    }

    @Test func failureContentModeApplied() async {
        // Given
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
        try? await loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.contentMode == .center)
    }

#endif

#if os(iOS) || os(tvOS) || os(visionOS)

    // MARK: - Tint Colors

    @Test func placeholderAndSuccessTintColorApplied() async throws {
        // Given
        options.tintColors = .init(
            success: .blue,
            failure: nil,
            placeholder: .yellow
        )
        options.placeholder = PlatformImage()

        // When
        try await loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.tintColor == .blue)
        #expect(imageView.image?.renderingMode == .alwaysTemplate)
    }

    @Test func successTintColorAppliedWhenFromMemoryCache() {
        // Given
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

    @Test func failureTintColorApplied() async throws {
        // Given
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
        try? await loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.tintColor == .red)
        #expect(imageView.image?.renderingMode == .alwaysTemplate)
    }

#endif

    // MARK: - Pipeline

    @Test func customPipelineUsed() async throws {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        var options = ImageLoadingOptions()
        options.pipeline = pipeline

        // When
        try await loadImage(with: Test.request, options: options, into: imageView)

        // Then
        _ = pipeline // retain
        #expect(dataLoader.createdTaskCount == 1)
        #expect(self.dataLoader.createdTaskCount == 0)
    }

    // MARK: - Cache Policy

    @Test func reloadIgnoringCachedData() async throws {
        // When the requested image is stored in memory cache
        var request = Test.request
        mockCache[request] = ImageContainer(image: PlatformImage())

        request.options = [.reloadIgnoringCachedData]

        // When
        try await loadImage(with: request, options: options, into: imageView)

        // Then
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Misc

#if os(iOS) || os(tvOS) || os(visionOS)
    @Test func transitionCrossDissolve() async throws {
        // Given
        options.placeholder = Test.image
        options.transition = .fadeIn(duration: 0.33)
        options.isPrepareForReuseEnabled = false
        options.contentModes = .init(
            success: .scaleAspectFill,
            failure: .center,
            placeholder: .center
        )

        imageView.image = Test.image

        // When
        try await loadImage(with: Test.request, options: options, into: imageView)

        // Then make sure we run the pass with cross-disolve and at least
        // it doesn't crash
    }
#endif

    @Test func settingDefaultProcessor() async throws {
        // Given
        options.processors = [MockImageProcessor(id: "p1")]

        // When
        try await loadImage(with: Test.request, options: options, into: imageView)

        // Then
        #expect(imageView.image?.nk_test_processorIDs == ["p1"])
    }
}

#endif
