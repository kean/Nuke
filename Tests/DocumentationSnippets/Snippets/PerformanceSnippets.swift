// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Performance/performance-guide.md`.

import Foundation
import Nuke

private func aggressiveDiskCache() {
    var configuration = ImagePipeline.Configuration.withDataCache()
    configuration.dataCachePolicy = .automatic

    ImagePipeline.shared = ImagePipeline(configuration: configuration)
}

private func downsampleImages() {
    let url = URL(string: "https://example.com/image")!
    // Target size is in points
    let request = ImageRequest(url: url, processors: [.resize(width: 320)])
    _ = request
}

private func coalescing(pipeline: ImagePipeline) {
    let url = URL(string: "https://example.com/image")

    // Only one network request is made for both of these
    let blurred = pipeline.imageTask(with: ImageRequest(url: url, processors: [
        .resize(size: CGSize(width: 44, height: 44)),
        .gaussianBlur(radius: 8)
    ]))
    let thumbnail = pipeline.imageTask(with: ImageRequest(url: url, processors: [
        .resize(size: CGSize(width: 44, height: 44))
    ]))
    _ = (blurred, thumbnail)
}

private func progressiveDecoding() {
    ImagePipeline.shared = ImagePipeline {
        $0.isProgressiveDecodingEnabled = true
    }
}

#if canImport(UIKit) && !os(watchOS)

import UIKit

private final class ImageView: UIView {
    private var task: ImageTask?

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)

        task?.priority = newWindow == nil ? .low : .high
    }
}

#endif
