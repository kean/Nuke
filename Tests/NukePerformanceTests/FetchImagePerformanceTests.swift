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
final class FetchImagePerformanceTests {
    private let seed = MemoryCacheSeed()

    @Test
    func fetchImageMainThreadPerformance() {
        let image = FetchImage()

        let urls = (0..<20_000).map { URL(string: "http://test.com/\($0)")! }

        measure {
            for url in urls {
                image.load(url)
            }
        }
    }

    @Test
    func fetchImageMainThreadPerformanceCacheHit() {
        let image = FetchImage()

        let requests = (0..<50_000).map { _ in ImageRequest(url: URL(string: "http://test.com/1")!) }
        for request in requests {
            ImagePipeline.shared.configuration.imageCache?[request] = ImageContainer(image: PlatformImage())
        }

        measure {
            for request in requests {
                image.load(request)
            }
        }
    }

    @Test
    func fetchImageMainThreadPerformanceWithProcessor() {
        let image = FetchImage()

        let urls = (0..<20_000).map { URL(string: "http://test.com/\($0)")! }

        measure {
            for url in urls {
                image.load(ImageRequest(url: url, processors: [ImageProcessors.Resize(size: CGSize(width: 1, height: 1))]))
            }
        }
    }

    @Test
    func fetchImageMainThreadPerformanceWithProcessorAndSimilarImageInCache() {
        let image = FetchImage()

        // The seed's URL, whose key has the same hash, so the lookup has to compare
        // the processors.
        let sizes = (1...20_000).map { CGSize(width: $0, height: 1) }

        measure {
            for size in sizes {
                image.load(ImageRequest(url: MemoryCacheSeed.url, processors: [ImageProcessors.Resize(size: size)]))
            }
        }
    }
}

#endif
