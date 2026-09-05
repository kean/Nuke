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

    @Test func fetchImageHasTheAnimationTheMomentTheResponseArrives() async throws {
        // The pipeline parses on the decoding queue and the animation travels
        // with the container, so there is no turn of the run loop between the
        // image and the animation to blink the still through.
        serve(Test.animatedGIF(frameCount: 18))
        let image = FetchImage()
        image.pipeline = pipeline
        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }

        image.load(Test.request)
        await expectation.wait()

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
    /// Gives a view a size and lays it out. A view with no size of its own
    /// waits for a layout before it builds a player, so that it never decodes
    /// a full-size frame for a size it is about to learn.
    private func layOut(_ view: HostedView) {
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
#if os(macOS)
        view.layoutSubtreeIfNeeded()
#else
        view.setNeedsLayout()
        view.layoutIfNeeded()
#endif
    }

    @Test func lazyImageViewPlaysAnimations() async throws {
        serve(Test.animatedGIF(frameCount: 3))
        let view = LazyImageView()
        view.pipeline = pipeline
        view.transition = nil
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }

        view.url = Test.url
        await expectation.wait()
        layOut(view)

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
        layOut(view)
        #expect(view.imageView.player != nil)

        view.reset()

        #expect(view.imageView.player == nil)
    }

    // MARK: Image View Extensions

    @Test func loadImageIntoAnAnimatedImageViewPlaysIt() async throws {
        // The path the display protocol redesign turns on: the container
        // reaches the view, animation and all, through a conformance the view
        // inherits from the platform image view extension and cannot override.
        serve(Test.animatedGIF(frameCount: 3))
        let view = AnimatedImageView()

        try await loadImage(into: view)
        layOut(view)

        let player = try #require(view.player)
        #expect(player.source.frameCount == 3)
    }

    @Test func loadImageIntoAnAnimatedImageViewShowsAStillAsAStill() async throws {
        serve(Test.data)
        let view = AnimatedImageView()

        try await loadImage(into: view)

        #expect(view.player == nil)
        #expect(view.image != nil)
    }

    @Test func loadImageIntoAPlainImageViewStillWorks() async throws {
        // The view has no animated conformance, so it takes the other branch
        // and is handed the still the decoder produced.
        serve(Test.animatedGIF(frameCount: 3))
        let view = _PlatformImageView()

        try await loadImage(into: view)

        #expect(view.image != nil)
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

    @Test func animatedImageShowsTheStillUntilTheFirstFrameIsDecoded() async throws {
        // A decoder held open, so that the first frame never arrives and what
        // is on screen is only ever the still the pipeline already produced.
        let (player, _, _) = AnimatedImageTest.makeGatedPlayer(frameCount: 4)
        let poster = Test.image
        let host = ViewHost(player) { AnimatedImage(player: $0, poster: poster) }

        await host.render(until: { host.firstView(ofType: AnimatedImageView.self) != nil })

        // Without the still, every animated cell – including one scrolled back
        // to, where the animation is already parsed – is blank for as long as
        // the first frame takes to decode.
        let view = try #require(host.firstView(ofType: AnimatedImageView.self))
        #expect(view.image === poster)
        #expect(player.image == nil)
    }

#if canImport(UIKit)
    @Test func animatedImageTakesItsScaleFromTheStill() async throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        let poster = UIImage(cgImage: Test.image.cgImage!, scale: 2, orientation: .up)
        let host = ViewHost(source) { AnimatedImage($0, poster: poster) }

        await host.render(until: { host.firstView(ofType: AnimatedImageView.self)?.player != nil })

        // The still is what the view reads the scale from, so an animation
        // without one plays at scale 1 and changes size when it starts.
        let view = try #require(host.firstView(ofType: AnimatedImageView.self))
        #expect(view.player?.options.scale == 2)
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

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
    /// Loads through the image view extensions and waits for the response.
    private func loadImage(into view: ImageDisplayingView) async throws {
        var options = ImageLoadingOptions()
        options.pipeline = pipeline
        options.transition = nil
        let expectation = TestExpectation()
        var result: Result<ImageResponse, ImagePipeline.Error>?
        NukeUI.loadImage(with: Test.url, options: options, into: view) {
            result = $0
            expectation.fulfill()
        }
        await expectation.wait()
        _ = try #require(result).get()
    }
#endif

    private func load(_ image: FetchImage) async throws {
        let expectation = TestExpectation()
        image.onCompletion = { _ in expectation.fulfill() }
        image.load(Test.request)
        await expectation.wait()
        _ = try #require(image.result?.value)
    }
}
