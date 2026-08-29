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
}

#endif
