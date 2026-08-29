// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import SwiftUI
import NukeUI // Deliberately the only Nuke import in this file.

/// NukeUI writes its API in Nuke types, so `import NukeUI` has to be enough to
/// use it. These tests stop compiling if the re-export is removed.
@Suite @MainActor
struct NukeUIExportsTests {
    @Test func lazyImage() {
        let request = ImageRequest(url: Self.url, processors: [ImageProcessors.Resize(width: 100)], priority: .high)
        let view = LazyImage(request: request)
            .processors([ImageProcessors.Circle()])
            .priority(.veryHigh)
            .pipeline(ImagePipeline.shared)
            .onStart { (task: ImageTask) in _ = task }
            .onCompletion { (result: Result<ImageResponse, ImagePipeline.Error>) in _ = result }

        #expect(request.priority == .high)
        withExtendedLifetime(view) {}
    }

    @Test func fetchImage() {
        let image = FetchImage()
        image.priority = .high
        image.pipeline = ImagePipeline.shared
        image.processors = [ImageProcessors.Resize(width: 100)]

        let container: ImageContainer? = image.imageContainer
        let result: Result<ImageResponse, ImagePipeline.Error>? = image.result

        #expect(container == nil)
        #expect(result == nil)
    }

#if !os(watchOS)
    @Test func lazyImageView() {
        let view = LazyImageView()
        view.priority = .high
        view.pipeline = ImagePipeline.shared
        view.processors = [ImageProcessors.Resize(width: 100)]
        view.onProgress = { (progress: ImageTask.Progress) in _ = progress }

        let request: ImageRequest? = view.request
        let task: ImageTask? = view.imageTask

        #expect(request == nil)
        #expect(task == nil)
    }
#endif

    private static let url = URL(string: "https://example.com/image.jpeg")
}
