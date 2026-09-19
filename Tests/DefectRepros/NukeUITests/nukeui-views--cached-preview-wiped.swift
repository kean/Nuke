// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

// BUG: `loadImage(with:options:into:)` displays a progressive preview found in
// the memory cache and then immediately overwrites it.
//
// Sources/NukeUI/ImageViewExtensions.swift, `ImageViewController.loadImage`:
//
//     if let image = pipeline.cache[request] {
//         display(image, true, .success)          // shows the cached preview
//         if !image.isPreview { ...; return nil }
//     }
//     if let placeholder = options.placeholder {
//         display(ImageContainer(image: placeholder), true, .placeholder)  // replaces it
//     } else if options.isPrepareForReuseEnabled {
//         imageView.nuke_display(nil)             // or clears it (default options)
//     }
//
// Expected: the cached preview stays on screen while the final image loads,
// which is what the code evidently intends (it displays the preview and only
// returns early when it is *not* a preview), and what `LazyImageView`
// (`memoryCachePreviewDisplayedThenFinalImage`) and `FetchImage` ("Display
// progressive image") do with the same cache entry.
//
// Actual: with the default options the view is empty until the final image
// arrives; with a placeholder the view shows the placeholder instead of the
// (much better) preview. The `display` call is wasted work.

@Suite(.timeLimit(.minutes(5))) @MainActor
struct ImageViewExtensionsCachedPreviewRepro {
    let dataLoader: MockDataLoader
    let imageCache: MockImageCache
    let options: ImageLoadingOptions
    let preview: ImageContainer

    init() {
        let dataLoader = MockDataLoader()
        dataLoader.isSuspended = true // The final image is still loading
        let imageCache = MockImageCache()
        let preview = ImageContainer(image: Test.image, isPreview: true)
        imageCache[Test.request] = preview
        self.dataLoader = dataLoader
        self.imageCache = imageCache
        self.preview = preview
        var options = ImageLoadingOptions()
        options.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
        }
        self.options = options
    }

    @Test func cachedPreviewStaysDisplayedWhileFinalImageLoads() {
        let imageView = _ImageView()

        let task = NukeUI.loadImage(with: Test.request, options: options, into: imageView)

        #expect(task != nil) // The final image is being loaded
        #expect(imageView.image === preview.image) // FAILS: the image is nil
    }

    @Test func cachedPreviewIsNotReplacedByPlaceholder() {
        let imageView = _ImageView()
        var options = options
        options.placeholder = Test.image

        NukeUI.loadImage(with: Test.request, options: options, into: imageView)

        #expect(imageView.image === preview.image) // FAILS: the placeholder is displayed
    }
}

#endif
