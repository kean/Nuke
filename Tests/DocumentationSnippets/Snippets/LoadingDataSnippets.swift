// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Customization/LoadingData/loading-data.md`.

import Foundation
import Nuke

private func failureCooldown() {
    let pipeline = ImagePipeline {
        $0.failureCooldown = .init(duration: 300)
    }
    _ = pipeline
}

private func skippingTheCooldown(pipeline: ImagePipeline, url: URL) async throws {
    let request = ImageRequest(url: url, options: [.skipFailureCooldown])
    let image = try await pipeline.image(for: request)
    _ = image
}

private func endingTheCooldown(pipeline: ImagePipeline) async {
    await pipeline.resetFailureCooldown()
}
