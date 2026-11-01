// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

#if !os(watchOS)

import Testing
import Foundation
import Nuke
import NukeUI

// A load of the image that is already loading keeps the running task and does
// next to nothing, so a benchmark of a load has to ask for another image every time.
@Suite(.serialized)
@MainActor
final class LazyImageViewPerformanceTests {
    private let seed = MemoryCacheSeed()

    @Test
    func lazyImageViewMainThreadPerformance() {
        let view = LazyImageView()

        let urls = (0..<20_000).map { _ in URL(string: "http://test.com/1")! }

        measure {
            for url in urls {
                view.url = url
            }
        }
    }

    @Test
    func lazyImageViewMainThreadPerformanceCacheHit() {
        let view = LazyImageView()

        let requests = (0..<50_000).map { _ in ImageRequest(url: URL(string: "http://test.com/1")!) }
        for request in requests {
            ImagePipeline.shared.configuration.imageCache?[request] = ImageContainer(image: PlatformImage())
        }

        measure {
            for request in requests {
                view.request = request
            }
        }
    }

    @Test
    func lazyImageViewMainThreadPerformanceWithProcessor() {
        let view = LazyImageView()

        let urls = (0..<20_000).map { URL(string: "http://test.com/\($0)")! }

        measure {
            for url in urls {
                view.request = ImageRequest(url: url, processors: [ImageProcessors.Resize(size: CGSize(width: 1, height: 1))])
            }
        }
    }

    @Test
    func lazyImageViewMainThreadPerformanceWithProcessorAndSimilarImageInCache() {
        let view = LazyImageView()

        // The seed's URL, whose key has the same hash, so the lookup has to compare
        // the processors.
        let sizes = (1...20_000).map { CGSize(width: $0, height: 1) }

        measure {
            for size in sizes {
                view.request = ImageRequest(url: MemoryCacheSeed.url, processors: [ImageProcessors.Resize(size: size)])
            }
        }
    }
}

#endif
