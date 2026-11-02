// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Customization/ImageProcessing/image-processing.md`.

import Foundation
import Nuke

private let url = URL(string: "https://example.com/image.jpeg")

private func geometryProcessors() -> ImageRequest {
    ImageRequest(url: url, processors: [
        .crop(rect: CGRect(x: 0, y: 0, width: 1200, height: 630), unit: .pixels),
        .rotate(degrees: 90),
        .flip(.horizontal)
    ])
}

private func tintProcessor() -> ImageRequest {
    ImageRequest(url: url, processors: [
        .tint(color: .black.withAlphaComponent(0.4))
    ])
}
