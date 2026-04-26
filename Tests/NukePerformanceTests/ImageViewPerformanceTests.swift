// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Nuke
import NukeExtensions

@Suite(.serialized)
@MainActor
final class ImageViewPerformanceTests {
    private let dummyCacheRequest = ImageRequest(url: URL(string: "http://test.com/9999999)")!, processors: [ImageProcessors.Resize(size: CGSize(width: 2, height: 2))])

    init() {
        // Store something in memory cache to avoid going through an optimized empty Dictionary path
        ImagePipeline.shared.configuration.imageCache?[dummyCacheRequest] = ImageContainer(image: PlatformImage())
    }

    deinit {
        ImagePipeline.shared.configuration.imageCache?[dummyCacheRequest] = nil
    }

    // This is the primary use case that we are optimizing for - loading images
    // into target, the API that majoriy of the apps are going to use.
    @Test
    func imageViewMainThreadPerformance() {
        let view = _ImageView()

        let urls = (0..<20_000).map { _ in URL(string: "http://test.com/1)")! }

        measure {
            for url in urls {
                NukeExtensions.loadImage(with: url, into: view)
            }
        }
    }

    @Test
    func imageViewMainThreadPerformanceCacheHit() {
        let view = _ImageView()

        let requests = (0..<50_000).map { _ in ImageRequest(url: URL(string: "http://test.com/1)")!) }
        for request in requests {
            ImagePipeline.shared.configuration.imageCache?[request] = ImageContainer(image: PlatformImage())
        }

        measure {
            for request in requests {
                NukeExtensions.loadImage(with: request, into: view)
            }
        }
    }

    @Test
    func imageViewMainThreadPerformanceWithProcessor() {
        let view = _ImageView()

        let urls = (0..<20_000).map { _ in URL(string: "http://test.com/1)")! }

        measure {
            for url in urls {
                let request = ImageRequest(url: url, processors: [ImageProcessors.Resize(size: CGSize(width: 1, height: 1))])
                NukeExtensions.loadImage(with: request, into: view)
            }
        }
    }

    @Test
    func imageViewMainThreadPerformanceWithProcessorAndSimilarImageInCache() {
        let view = _ImageView()

        let urls = (0..<20_000).map { _ in URL(string: "http://test.com/9999999)")! }

        measure {
            for url in urls {
                let request = ImageRequest(url: url, processors: [ImageProcessors.Resize(size: CGSize(width: 1, height: 1))])
                NukeExtensions.loadImage(with: request, into: view)
            }
        }
    }
}
