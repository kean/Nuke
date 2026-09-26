// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

#if !os(watchOS)

import Testing
import Foundation
import Nuke
import NukeUI

@Suite(.serialized)
@MainActor
final class FetchImagePerformanceTests {
    private let seed = MemoryCacheSeed()

    @Test
    func fetchImageMainThreadPerformance() {
        let image = FetchImage()

        let urls = (0..<20_000).map { _ in URL(string: "http://test.com/1")! }

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

        let urls = (0..<20_000).map { _ in URL(string: "http://test.com/1")! }

        measure {
            for url in urls {
                image.load(ImageRequest(url: url, processors: [ImageProcessors.Resize(size: CGSize(width: 1, height: 1))]))
            }
        }
    }

    @Test
    func fetchImageMainThreadPerformanceWithProcessorAndSimilarImageInCache() {
        let image = FetchImage()

        let urls = (0..<20_000).map { _ in MemoryCacheSeed.url }

        measure {
            for url in urls {
                image.load(ImageRequest(url: url, processors: [ImageProcessors.Resize(size: CGSize(width: 1, height: 1))]))
            }
        }
    }
}

#endif
