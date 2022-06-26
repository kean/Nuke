// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

private let pipeline = ImagePipeline.shared
private let url = URL(string: "https://example.com/image.jpeg")!
private let imageView = _ImageView()

// MARK: - Getting Started

private func checkGettingStarted01() async throws {
    let response = try await ImagePipeline.shared.image(for: url)
    let image = response.image

    _ = image
}

private final class CheckGettingStarted02: ImageTaskDelegate {
    func loadImage() async throws {
        let _ = try await pipeline.image(for: url, delegate: self)
    }

    func imageTaskCreated(_ task: ImageTask) {
        // Gets called immediately when the task is created.
    }

    func imageTask(_ task: ImageTask, didReceivePreview response: ImageResponse) {
        // Gets called for images that support progressive decoding.
    }

    func imageTask(_ task: ImageTask, didUpdateProgress progress: ImageTask.Progress) {
        // Gets called when the download progress is updated.
    }
}

@MainActor
private func checkGettingStarted03() async throws {
    let request = ImageRequest(
        url: URL(string: "http://example.com/image.jpeg"),
        processors: [.resize(size: imageView.bounds.size)],
        priority: .high,
        options: [.reloadIgnoringCachedData]
    )
    let response = try await pipeline.image(for: request)

    _ = response
}

private func checkGettingStarted04() {
    ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
}
