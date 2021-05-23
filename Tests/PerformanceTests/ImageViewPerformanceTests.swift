// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ImageViewPerformanceTests: XCTestCase {
    private let dummyCacheRequest = ImageRequest(url: URL(string: "http://test.com/9999999)")!, processors: [ImageProcessors.Resize(size: CGSize(width: 2, height: 2))])

    override func setUp() {
        // Store something in memory cache to avoid going through an optimized empty Dictionary path
        ImagePipeline.shared.configuration.imageCache?[dummyCacheRequest] = ImageContainer(image: PlatformImage())
    }

    override func tearDown() {
        ImagePipeline.shared.configuration.imageCache?[dummyCacheRequest] = nil
    }

    // This is the primary use case that we are optimizing for - loading images
    // into target, the API that majoriy of the apps are going to use.
    func testImageViewMainThreadPerformance() {
        let view = _ImageView()

        let urls = (0..<20_000).map { _ in return URL(string: "http://test.com/1)")! }

        measure {
            for url in urls {
                loadImage(with: url, into: view)
            }
        }
    }

    func testImageViewMainThreadPerformanceCacheHit() {
        let view = _ImageView()

        let urls = (0..<50_000).map { _ in return URL(string: "http://test.com/1)")! }
        for url in urls {
            ImagePipeline.shared.configuration.imageCache?[url] = ImageContainer(image: PlatformImage())
        }

        measure {
            for url in urls {
                loadImage(with: url, into: view)
            }
        }
    }

    func testImageViewMainThreadPerformanceWithProcessor() {
        let view = _ImageView()

        let urls = (0..<20_000).map { _ in return URL(string: "http://test.com/1)")! }

        measure {
            for url in urls {
                let request = ImageRequest(url: url, processors: [ImageProcessors.Resize(size: CGSize(width: 1, height: 1))])
                loadImage(with: request, into: view)
            }
        }
    }

    func testImageViewMainThreadPerformanceWithProcessorAndSimilarImageInCache() {
        let view = _ImageView()

        let urls = (0..<20_000).map { _ in return URL(string: "http://test.com/9999999)")! }

        measure {
            for url in urls {
                let request = ImageRequest(url: url, processors: [ImageProcessors.Resize(size: CGSize(width: 1, height: 1))])
                loadImage(with: request, into: view)
            }
        }
    }
}
