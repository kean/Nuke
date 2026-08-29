// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

/// Covers the path an animated image takes from the pipeline to the views: the
/// decoder attaches the data, ``FetchImage`` parses it once, and the views play
/// it without being asked to.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageIntegrationTests {
    let dataLoader = MockDataLoader()
    let pipeline: ImagePipeline

    init() {
        let dataLoader = self.dataLoader
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
        }
    }

    // MARK: FetchImage

    @Test func fetchImageParsesTheAnimation() async throws {
        serve(Test.animatedGIF(frameCount: 5))
        let image = FetchImage()
        image.pipeline = pipeline

        try await load(image)

        let animatedImage = try #require(image.animatedImage)
        #expect(animatedImage.frameCount == 5)
        #expect(image.imageContainer?.data != nil)
    }

    @Test func fetchImageParsesTheAnimationOnlyOnce() async throws {
        serve(Test.animatedGIF())
        let image = FetchImage()
        image.pipeline = pipeline

        try await load(image)

        // Reading it twice returns the value parsed when the response arrived,
        // not a fresh parse of the container.
        #expect(image.animatedImage === image.animatedImage)
    }

    @Test func fetchImageHasNoAnimationForAStillImage() async throws {
        serve(Test.data)
        let image = FetchImage()
        image.pipeline = pipeline

        try await load(image)

        #expect(image.imageContainer != nil)
        #expect(image.animatedImage == nil)
    }

    @Test func fetchImageClearsTheAnimationOnReset() async throws {
        serve(Test.animatedGIF())
        let image = FetchImage()
        image.pipeline = pipeline
        try await load(image)
        #expect(image.animatedImage != nil)

        image.reset()

        #expect(image.animatedImage == nil)
    }

    // MARK: Processing

    @Test func processedAnimationIsDisplayedAsAStill() async throws {
        // The processor produced a new image; playing the original animation
        // over it would show something the app never asked for.
        serve(Test.animatedGIF(size: CGSize(width: 40, height: 40)))
        let image = FetchImage()
        image.pipeline = pipeline
        image.processors = [ImageProcessors.Resize(size: CGSize(width: 10, height: 10), unit: .pixels)]

        try await load(image)

        #expect(image.imageContainer != nil)
        #expect(image.animatedImage == nil)
    }

    // MARK: LazyImageView

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
    @Test func lazyImageViewPlaysAnimations() async throws {
        serve(Test.animatedGIF(frameCount: 3))
        let view = LazyImageView()
        view.pipeline = pipeline
        view.transition = nil
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }

        view.url = Test.url
        await expectation.wait()

        let player = try #require(view.imageView.player)
        #expect(player.source.frameCount == 3)
    }

    @Test func lazyImageViewShowsStillImagesAsStills() async throws {
        serve(Test.data)
        let view = LazyImageView()
        view.pipeline = pipeline
        view.transition = nil
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }

        view.url = Test.url
        await expectation.wait()

        #expect(view.imageView.player == nil)
        #expect(view.imageView.image != nil)
    }

    @Test func lazyImageViewStopsTheAnimationOnReset() async throws {
        serve(Test.animatedGIF())
        let view = LazyImageView()
        view.pipeline = pipeline
        view.transition = nil
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = Test.url
        await expectation.wait()
        #expect(view.imageView.player != nil)

        view.reset()

        #expect(view.imageView.player == nil)
    }
#endif

    // MARK: Helpers

    private func serve(_ data: Data) {
        dataLoader.results[Test.url] = .success((data, URLResponse(
            url: Test.url,
            mimeType: "image/gif",
            expectedContentLength: data.count,
            textEncodingName: nil
        )))
    }

    private func load(_ image: FetchImage) async throws {
        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }
        image.load(Test.request)
        await expectation.wait()
        _ = try #require(image.result?.value)
    }
}
