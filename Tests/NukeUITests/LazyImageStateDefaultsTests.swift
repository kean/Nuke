// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

/// The protocol's defaults, seen through a conformance other than `FetchImage`:
/// an app can drive its `LazyImage` content from a state of its own, such as
/// in previews.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct LazyImageStateDefaultsTests {
    @MainActor
    private struct StaticState: LazyImageState {
        var result: Result<ImageResponse, ImagePipeline.Error>?
        var imageContainer: ImageContainer?
        var isLoading = false
        var progress = ImageTask.Progress(completed: 0, total: 0)
    }

    @Test func emptyStateHasNoImageErrorOrAnimation() {
        let state = StaticState()
        #expect(state.image == nil)
        #expect(state.error == nil)
        #expect(state.animatedImage == nil)
    }

    @Test func imageIsReadFromTheContainerEvenWithoutAResult() {
        // A progressive preview arrives before any result.
        let state = StaticState(imageContainer: ImageContainer(image: Test.image, isPreview: true), isLoading: true)
        #expect(state.image != nil)
        #expect(state.error == nil)
    }

    @Test func animatedImageIsReadFromTheContainer() {
        let source = Test.animatedGIFSource(frameCount: 3)
        let container = ImageContainer(image: Test.image, animation: source)
        let state = StaticState(imageContainer: container)
        #expect(state.animatedImage === source)
    }
}
