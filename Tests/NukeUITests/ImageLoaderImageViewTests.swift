// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Covers what an image view displays when an ``ImageLoader`` loads into it.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct ImageLoaderImageViewTests {
    let dataLoader: MockDataLoader
    let imageCache: MockImageCache
    let pipeline: ImagePipeline
    let imageView = _PlatformImageView()
    let placeholder = Test.image(named: "fixture-tiny", extension: "jpeg")
    let failureImage = Test.image(named: "fixture-tiny", extension: "jpeg")

    init() {
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        self.dataLoader = dataLoader
        self.imageCache = imageCache
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = MockDataCache()
        }
    }

    @Test func memoryCacheHitIsDisplayedSynchronously() {
        // Given
        let container = Test.container
        imageCache[Test.request] = container

        // When
        ImageLoader.load(Test.request, into: imageView, pipeline: pipeline)

        // Then
        #expect(imageView.image === container.image)
    }

    @Test func loadedImageIsDisplayed() async throws {
        // When
        let response = try await ImageLoader.load(Test.request, into: imageView, pipeline: pipeline).response

        // Then
        #expect(imageView.image === response.image)
    }

    @Test func placeholderIsDisplayedWhileLoading() async throws {
        // Given
        dataLoader.isSuspended = true

        // When
        let handle = ImageLoader.load(Test.request, into: imageView, presentation: .init(placeholder: placeholder), pipeline: pipeline)

        // Then
        #expect(imageView.image === placeholder)

        // When the image arrives
        dataLoader.isSuspended = false
        let response = try await handle.response

        // Then it replaces the placeholder
        #expect(imageView.image === response.image)
    }

    @Test func previousImageIsClearedWhenNewLoadStarts() async throws {
        // Given
        _ = try await ImageLoader.load(Test.request, into: imageView, pipeline: pipeline).response
        #expect(imageView.image != nil)

        // When
        dataLoader.isSuspended = true
        ImageLoader.load(URL(string: "https://example.com/other.jpg")!, into: imageView)

        // Then
        #expect(imageView.image == nil)
    }

    @Test func previousImageIsKeptWhenLoaderKeepsIt() async throws {
        // Given
        let response = try await ImageLoader.load(Test.request, into: imageView, pipeline: pipeline).response
        ImageLoader.loader(for: imageView).keepsPreviousImage = true

        // When
        dataLoader.isSuspended = true
        ImageLoader.load(URL(string: "https://example.com/other.jpg")!, into: imageView, presentation: .init(placeholder: placeholder))

        // Then
        #expect(imageView.image === response.image)
    }

    @Test func failureImageIsDisplayedOnFailure() async {
        // Given
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))

        // When
        let result = await ImageLoader.load(Test.request, into: imageView, presentation: .init(placeholder: placeholder, failureImage: failureImage), pipeline: pipeline).result

        // Then
        #expect(result.error != nil)
        #expect(imageView.image === failureImage)
    }

    @Test func placeholderIsKeptOnFailureWithoutFailureImage() async {
        // Given
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))

        // When
        _ = await ImageLoader.load(Test.request, into: imageView, presentation: .init(placeholder: placeholder), pipeline: pipeline).result

        // Then
        #expect(imageView.image === placeholder)
    }

    @Test func nilRequestDisplaysTheFailureImage() {
        // When
        ImageLoader.load(nil as URL?, into: imageView, presentation: .init(failureImage: failureImage), pipeline: pipeline)

        // Then
        #expect(imageView.image === failureImage)
    }

    @Test func customTransitionRunsForLoadedImages() async throws {
        // Given
        var displayed: [PlatformImage] = []
        let presentation = ImageLoader.Presentation(transition: .custom { imageView, container in
            imageView.image = container.image
            displayed.append(container.image)
        })

        // When
        let response = try await ImageLoader.load(Test.request, into: imageView, presentation: presentation, pipeline: pipeline).response

        // Then
        #expect(displayed.count == 1)
        #expect(displayed.first === response.image)
    }

    @Test func customTransitionDoesNotRunForMemoryCacheHit() {
        // Given
        let container = Test.container
        imageCache[Test.request] = container
        var transitionCount = 0
        let presentation = ImageLoader.Presentation(transition: .custom { _, _ in
            transitionCount += 1
        })

        // When
        ImageLoader.load(Test.request, into: imageView, presentation: presentation, pipeline: pipeline)

        // Then
        #expect(transitionCount == 0)
        #expect(imageView.image === container.image)
    }

    @Test func resetClearsTheImageView() {
        // Given
        imageCache[Test.request] = Test.container
        ImageLoader.load(Test.request, into: imageView, pipeline: pipeline)

        // When
        ImageLoader.loader(for: imageView).reset()

        // Then
        #expect(imageView.image == nil)
    }
}

#endif
