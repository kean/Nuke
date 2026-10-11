// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeExtensions
@testable import NukeUI
#if os(macOS)
import AppKit
#endif

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

/// Covers the image view extensions handing an animated image to an
/// `AnimatedImageView`, which plays it, and to a plain image view, which shows
/// the still.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct ImageViewExtensionsAnimatedImageTests {
    private let fixture = ImageViewFixture()

    @Test func loadImageIntoAnAnimatedImageViewPlaysIt() async throws {
        // The container reaches the view, animation and all, through a
        // conformance the view inherits from the platform image view extension
        // and cannot override.
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

    // MARK: Helpers

    private func serve(_ data: Data) {
        fixture.dataLoader.results[Test.url] = .success((data, URLResponse(
            url: Test.url,
            mimeType: "image/gif",
            expectedContentLength: data.count,
            textEncodingName: nil
        )))
    }

    /// Gives a view a size and lays it out. A view with no size of its own
    /// waits for a layout before it builds a player, so that it never decodes
    /// a full-size frame for a size it is about to learn.
    private func layOut(_ view: ImageDisplayingView) {
#if os(macOS)
        guard let view = view as? NSView else { return }
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        view.layoutSubtreeIfNeeded()
#else
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        view.setNeedsLayout()
        view.layoutIfNeeded()
#endif
    }

    /// Loads through the image view extensions and waits for the response.
    private func loadImage(into view: ImageDisplayingView) async throws {
        var options = fixture.options
        options.transition = nil
        let expectation = TestExpectation()
        var result: Result<ImageResponse, ImagePipeline.Error>?
        NukeExtensions.loadImage(with: Test.url, options: options, into: view) {
            result = $0
            expectation.fulfill()
        }
        await expectation.wait()
        _ = try #require(result).get()
    }
}

#endif
