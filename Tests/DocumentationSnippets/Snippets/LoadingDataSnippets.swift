// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Customization/LoadingData/loading-data.md`
// that aren't about a custom data loader.

import Foundation
import Nuke

private func fallbackSources(placeholder: PlatformImage) async throws {
    var request = ImageRequest(url: URL(string: "https://cdn.example.com/photo.jpeg"))
    request.alternatives = [
        .url(URL(string: "https://mirror.example.com/photo.jpeg")),
        .image(id: "photo-placeholder") { ImageContainer(image: placeholder) }
    ]
    let response = try await ImagePipeline.shared.imageTask(with: request).response
    print(response.request.url as Any) // The source the image came from
}

private func lowDataMode() {
    var request = ImageRequest(url: URL(string: "https://example.com/photo@3x.jpeg"))
    request.lowDataURL = URL(string: "https://example.com/photo@1x.jpeg")
    _ = request
}
