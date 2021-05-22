// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ImagePipelinePerfomanceTests: XCTestCase {
    /// A very broad test that establishes how long in general it takes to load
    /// data, decode, and decomperss 50+ images. It's very useful to get a
    /// broad picture about how loader options affect perofmance.
    func testLoaderOverallPerformance() {
        struct MockDecoder: ImageDecoding {
            static let container = ImageContainer(image: Test.image)

            func decode(_ data: Data) -> ImageContainer? {
                MockDecoder.container
            }
        }

        let pipeline = ImagePipeline {
            $0.imageCache = nil

            $0.dataLoader = MockDataLoader()

            $0.isDecompressionEnabled = false

            // This must be off for this test, because rate limiter is optimized for
            // the actual loading in the apps and not the syntetic tests like this.
            $0.isRateLimiterEnabled = false

            // Remove decoding from the equation
            $0.makeImageDecoder = { _ in ImageDecoders.Empty() }
        }

        let urls = (0...5000).map { URL(string: "http://test.com/\($0)")! }
        let callbackQueue = DispatchQueue(label: "testLoaderOverallPerformance")
        measure {
            var finished: Int = 0
            let semaphore = DispatchSemaphore(value: 0)
            for url in urls {
                pipeline.loadImage(with: url, queue: callbackQueue, progress: nil) { _ in
                    finished += 1
                    if finished == urls.count {
                        semaphore.signal()
                    }
                }
            }
            semaphore.wait()
        }
    }
}
