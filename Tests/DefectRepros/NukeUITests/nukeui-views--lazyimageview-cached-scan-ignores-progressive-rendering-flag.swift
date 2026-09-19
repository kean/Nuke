// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

// BUG: `LazyImageView.isProgressiveImageRenderingEnabled = false` doesn't stop
// the view from displaying a progressive scan when the scan comes from the
// memory cache.
//
// Sources/NukeUI/LazyImageView.swift, `load(_:)`:
//
//     if let image = cachedImage, image.isPreview {
//         display(image, isFromMemory: true)   // no isProgressiveImageRenderingEnabled check
//     }
//
// while the scans delivered by the pipeline go through `handle(preview:)`,
// which returns early when the flag is off.
//
// Expected: "If disabled, progressive image scans will be ignored" – the view
// keeps showing the placeholder until the final image arrives, the same as for
// the scans produced during the load (`progressivePreviewsIgnoredWhenRenderingDisabled`).
//
// Actual: a scan stored in the memory cache (`isStoringPreviewsInMemoryCache`,
// on by default) is displayed, and stays on screen for the whole load. An app
// that disabled progressive rendering to avoid showing blurry partial images
// shows one whenever the same URL was partially loaded before, e.g. by a
// cancelled request in a scrolled-away cell.

@Suite(.timeLimit(.minutes(5))) @MainActor
struct LazyImageViewCachedScanRenderingRepro {
    @Test func cachedScanIsIgnoredWhenProgressiveRenderingIsDisabled() {
        // Given a progressive scan in the memory cache
        let dataLoader = MockDataLoader()
        dataLoader.isSuspended = true // The final image is still loading
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
        }
        pipeline.cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        let view = LazyImageView()
        view.pipeline = pipeline
        view.transition = nil
        view.isProgressiveImageRenderingEnabled = false
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder

        // When
        view.request = Test.request

        // Then
        #expect(view.imageTask != nil) // The final image is being loaded
        #expect(!placeholder.isHidden)
        #expect(view.imageView.isHidden) // FAILS: the cached scan is displayed
        #expect(view.imageView.image == nil) // FAILS
    }
}

#endif
