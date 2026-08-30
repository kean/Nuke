// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import SwiftUI
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

    @Test func fetchImageReusesAnAnimationItHasSeenBefore() async throws {
        // Parsing is off the main thread, but only when there is a parse to do:
        // an animation already in the cache arrives with the image, and a list
        // scrolled back to one does not blink through the still.
        let data = Test.animatedGIF(frameCount: 18)
        _ = AnimatedImageSource.cached(data: data)
        serve(data)
        let image = FetchImage()
        image.pipeline = pipeline
        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }

        image.load(Test.request)
        await expectation.wait()

        #expect(image.animatedImageTask == nil)
        #expect(image.animatedImage?.frameCount == 18)
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
        await view.imageView.pendingParse?.value

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
        await view.imageView.pendingParse?.value
        #expect(view.imageView.player != nil)

        view.reset()

        #expect(view.imageView.player == nil)
    }

    // MARK: AnimatedImage

    @Test func animatedImagePlaysWithoutBeingAsked() async throws {
        // Playback starts on its own unless Accessibility › Motion › Auto-Play
        // Animated Images says not to, which the view reads from the SwiftUI
        // environment – and which is on wherever the tests run.
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        let host = ViewHost(source) { AnimatedImage($0) }

        await host.render(until: { host.firstView(ofType: AnimatedImageView.self)?.isPlaying == true })

        let view = try #require(host.firstView(ofType: AnimatedImageView.self))
        #expect(view.isPlaybackEnabled)
        #expect(view.isPlaying)
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
        // An animation it hasn't seen before is parsed off the main thread.
        await image.animatedImageTask?.value
        _ = try #require(image.result?.value)
    }
}
