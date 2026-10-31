// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
import Accessibility
@testable import Nuke
@testable import NukeUI

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// The views follow settings of the test's own, because nothing lets a test
// change the system's. `AnimatedImageRepresentableTests` covers SwiftUI.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageAutoPlaySettingsTests {
    let view = AnimatedImageView()

    private func makeSettings(isAutoPlayEnabled: Bool = true, isReduceMotionEnabled: Bool = false) -> AnimatedImageAutoPlaySettings {
        let settings = AnimatedImageAutoPlaySettings(isAutoPlayEnabled: isAutoPlayEnabled, isReduceMotionEnabled: isReduceMotionEnabled)
        view.autoPlaySettings = settings
        return settings
    }

    // MARK: Reading

    @Test(arguments: [
        (true, false, true),
        (false, false, false),
        (true, true, false),
        (false, true, false)
    ]) func playbackNeedsAutoPlayOnAndReduceMotionOff(isAutoPlayEnabled: Bool, isReduceMotionEnabled: Bool, allowsPlayback: Bool) {
        let settings = AnimatedImageAutoPlaySettings(isAutoPlayEnabled: isAutoPlayEnabled, isReduceMotionEnabled: isReduceMotionEnabled)

        #expect(settings.allowsPlayback == allowsPlayback)
    }

    @Test func followsTheSystemByDefault() throws {
        let settings = AnimatedImageAutoPlaySettings()

        #expect(view.autoPlaySettings === AnimatedImageAutoPlaySettings.shared)
#if os(macOS)
        #expect(settings.isReduceMotionEnabled == NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
#else
        #expect(settings.isReduceMotionEnabled == UIAccessibility.isReduceMotionEnabled)
#endif
        if #available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, *) {
            #expect(settings.isAutoPlayEnabled == AccessibilitySettings.animatedImagesEnabled)
        }
    }

    // MARK: Starting

    @Test func holdsStillWhileAutoPlayIsOff() {
        _ = makeSettings(isAutoPlayEnabled: false)
        let host = TestWindow(view: view)

        view.animation = Test.animatedGIFSource()

        #expect(view.isPlaying == false)
        host.close()
    }

    @Test func holdsStillWhileReduceMotionIsOn() {
        _ = makeSettings(isReduceMotionEnabled: true)
        let host = TestWindow(view: view)

        view.animation = Test.animatedGIFSource()

        #expect(view.isPlaying == false)
        host.close()
    }

    @Test func playsWhileNeitherSettingSaysOtherwise() {
        _ = makeSettings()
        let host = TestWindow(view: view)

        view.animation = Test.animatedGIFSource()

        #expect(view.isPlaying)
        host.close()
    }

    @Test func holdingStillShowsTheFirstFrameWithoutFillingTheBuffer() async throws {
        _ = makeSettings(isAutoPlayEnabled: false)
        let host = TestWindow(view: view)
        view.animation = Test.animatedGIFSource(frameCount: 8)
        let player = try #require(view.player)

        await player.waitUntilFull()

        #expect(view.image === player.image)
        #expect(player.currentFrameIndex == 0)
        #expect(player.diagnostics.bufferedFrameCount <= AnimatedImagePlayer.idleFrameCount)
        host.close()
    }

    @Test func aPlayButtonStillWorks() throws {
        // The setting is about what starts on its own. Somebody tapping play
        // asked to see this one.
        _ = makeSettings(isAutoPlayEnabled: false)
        let host = TestWindow(view: view)
        view.animation = Test.animatedGIFSource()

        try #require(view.player).play()

        #expect(view.isPlaying)
        host.close()
    }

    // MARK: Changing While Running

    @Test func pausesInPlaceAndResumesWhenAutoPlayChanges() throws {
        let settings = makeSettings()
        let host = TestWindow(view: view)
        view.animation = Test.animatedGIFSource(frameCount: 8)
        let player = try #require(view.player)
        player.seek(toFrame: 5)
        #expect(view.isPlaying)

        settings.update(isAutoPlayEnabled: false, isReduceMotionEnabled: false)

        #expect(view.isPlaying == false)
        #expect(player.currentFrameIndex == 5)

        settings.update(isAutoPlayEnabled: true, isReduceMotionEnabled: false)

        #expect(view.isPlaying)
        #expect(view.player === player)
        #expect(player.currentFrameIndex == 5)
        host.close()
    }

    @Test func pausesInPlaceAndResumesWhenReduceMotionChanges() throws {
        let settings = makeSettings()
        let host = TestWindow(view: view)
        view.animation = Test.animatedGIFSource(frameCount: 8)
        let player = try #require(view.player)
        player.seek(toFrame: 5)
        #expect(view.isPlaying)

        settings.update(isAutoPlayEnabled: true, isReduceMotionEnabled: true)

        #expect(view.isPlaying == false)
        #expect(player.currentFrameIndex == 5)

        settings.update(isAutoPlayEnabled: true, isReduceMotionEnabled: false)

        #expect(view.isPlaying)
        #expect(view.player === player)
        host.close()
    }

    @Test func staysStillUntilBothSettingsAllowIt() {
        let settings = makeSettings(isAutoPlayEnabled: false, isReduceMotionEnabled: true)
        let host = TestWindow(view: view)
        view.animation = Test.animatedGIFSource()

        settings.update(isAutoPlayEnabled: true, isReduceMotionEnabled: true)
        #expect(view.isPlaying == false)

        settings.update(isAutoPlayEnabled: true, isReduceMotionEnabled: false)
        #expect(view.isPlaying)
        host.close()
    }

    @Test func aChangeDoesNotStartAViewThatIsOffScreen() {
        let settings = makeSettings(isAutoPlayEnabled: false)
        view.animation = Test.animatedGIFSource()

        settings.update(isAutoPlayEnabled: true, isReduceMotionEnabled: false)

        #expect(view.window == nil)
        #expect(view.isPlaying == false)
    }

    @Test func aChangeDoesNotStartAViewWithPlaybackDisabled() {
        let settings = makeSettings(isAutoPlayEnabled: false)
        let host = TestWindow(view: view)
        view.isPlaybackEnabled = false
        view.animation = Test.animatedGIFSource()

        settings.update(isAutoPlayEnabled: true, isReduceMotionEnabled: false)

        #expect(view.isPlaying == false)
        host.close()
    }

    @Test func aViewCarriesOnThroughANewAnimation() throws {
        // Following the settings is once per view, not once per animation.
        let settings = makeSettings()
        let host = TestWindow(view: view)
        view.animation = Test.animatedGIFSource()
        view.animation = Test.animatedGIFSource()

        settings.update(isAutoPlayEnabled: false, isReduceMotionEnabled: false)

        #expect(view.isPlaying == false)
        host.close()
    }

    @Test func doesNotKeepAViewAlive() {
        let settings = AnimatedImageAutoPlaySettings(isAutoPlayEnabled: true, isReduceMotionEnabled: false)
        weak var released: AnimatedImageView?
        autoreleasepool {
            let view = AnimatedImageView()
            view.autoPlaySettings = settings
            view.animation = Test.animatedGIFSource()
            released = view
        }

        #expect(released == nil)
        // Whatever is left in the table is nothing the update can trip over.
        settings.update(isAutoPlayEnabled: false, isReduceMotionEnabled: false)
    }

    // MARK: Through the Other Surfaces

    @Test func aLazyImageViewHoldsStill() async throws {
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = MockImageCache()
        }
        let lazyImageView = LazyImageView()
        lazyImageView.pipeline = pipeline
        let settings = AnimatedImageAutoPlaySettings(isAutoPlayEnabled: false, isReduceMotionEnabled: false)
        lazyImageView.imageView.autoPlaySettings = settings
        lazyImageView.imageView.isAutomaticDownsamplingEnabled = false
        let host = TestWindow(view: lazyImageView)
        let request = ImageRequest(url: Test.url)
        pipeline.cache[request] = try ImageDecoders.Default().decode(Test.animatedGIF())

        lazyImageView.request = request

        let player = try #require(lazyImageView.imageView.player)
        #expect(lazyImageView.imageView.isPlaying == false)

        settings.update(isAutoPlayEnabled: true, isReduceMotionEnabled: false)

        #expect(player.isPlaying)
        host.close()
    }

    @Test func imageLoaderHoldsStill() throws {
        _ = makeSettings(isReduceMotionEnabled: true)
        let host = TestWindow(view: view)
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = MockImageCache()
        }
        let request = ImageRequest(url: Test.url)
        pipeline.cache[request] = try ImageDecoders.Default().decode(Test.animatedGIF())

        ImageLoader.load(request, into: view, pipeline: pipeline)

        #expect(view.player != nil)
        #expect(view.isPlaying == false)
        host.close()
    }
}

#endif
