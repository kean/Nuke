// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

/// A processor that processes the image the way ``MockImageProcessor`` does
/// and keeps the rest of the container – the encoded data and the animation
/// included – the way a processor that transforms every frame of an animation
/// does.
struct MockDataPreservingProcessor: ImageProcessing {
    let identifier: String

    init(id: String) {
        self.identifier = id
    }

    func process(_ image: PlatformImage) -> PlatformImage? {
        MockImageProcessor(id: identifier).process(image)
    }

    func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
        guard let image = process(container.image) else {
            throw ImageProcessingError.unknown
        }
        var container = container
        container.image = image
        return container
    }
}
