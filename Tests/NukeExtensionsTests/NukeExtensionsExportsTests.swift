// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import NukeExtensions // Deliberately the only Nuke import in this file.

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

/// NukeExtensions writes its API in Nuke types, so `import NukeExtensions` has
/// to be enough to use it. These tests stop compiling if the re-export is removed.
@Suite @MainActor
struct NukeExtensionsExportsTests {
    @Test func imageLoadingOptions() {
        var options = ImageLoadingOptions()
        options.pipeline = ImagePipeline.shared
        options.processors = [ImageProcessors.Resize(width: 100)]

        #expect(options.pipeline != nil)
        #expect(options.processors.count == 1)
    }

    @Test func loadImageIntoView() {
        var options = ImageLoadingOptions()
        options.pipeline = ImagePipeline { $0.dataLoader = MockDataLoader() }

        let view: ImageDisplayingView = _ImageView()
        let request = ImageRequest(url: URL(string: "https://example.com/image.jpeg"))
        let task: ImageTask? = loadImage(with: request, options: options, into: view) { (result: Result<ImageResponse, ImagePipeline.Error>) in
            _ = result
        }
        task?.cancel()
        cancelRequest(for: view)

        #expect(task != nil)
    }

    /// NukeExtensions is a shim for all of NukeUI, not only for the image view
    /// extensions that moved there, so an app that still imports it keeps
    /// seeing the rest of NukeUI as well.
    @Test func nukeUIComponents() {
        let pipeline = ImagePipeline { $0.dataLoader = MockDataLoader() }

        let view = LazyImageView()
        view.pipeline = pipeline
        let image = FetchImage()
        image.pipeline = pipeline

        #expect(view.request == nil)
        #expect(image.imageContainer == nil)
        #expect(!image.isLoading)
    }
}

#endif
