// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

/// An image the main-thread benchmarks keep in the shared memory cache for as
/// long as their suite lives, so that a lookup doesn't take the path an empty
/// `Dictionary` is optimized for.
final class MemoryCacheSeed {
    /// The URL of the image, which the "similar image in cache" benchmarks
    /// load with another processor.
    static let url = URL(string: "http://test.com/9999999")!

    private let request = ImageRequest(url: MemoryCacheSeed.url, processors: [ImageProcessors.Resize(size: CGSize(width: 2, height: 2))])

    init() {
        ImagePipeline.shared.configuration.imageCache?[request] = ImageContainer(image: PlatformImage())
    }

    deinit {
        ImagePipeline.shared.configuration.imageCache?[request] = nil
    }
}
