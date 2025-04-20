// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ImagePipelinePerfomanceTests: XCTestCase {
    /// A very broad test that establishes how long in general it takes to load
    /// data, decode, and decomperss 50+ images. It's very useful to get a
    /// broad picture about how loader options affect perofmance.
    func testLoaderOverallPerformance() {
        let pipeline = makePipeline()

        let requests = (0...5000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")) }

        measure {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                await withTaskGroup(of: Void.self) { group in
                    for request in requests {
                        group.addTask {
                            _ = try? await pipeline.image(for: request)
                        }
                    }
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
    }

    func testAsyncImageTaskEventsPerformance() {
        let pipeline = makePipeline()

        let requests = (0...5000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")) }

        measure {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                await withTaskGroup(of: Void.self) { group in
                    for request in requests {
                        group.addTask {
                            let imageTask = pipeline.imageTask(with: request)
                            for await event in imageTask.events {
                                _ = event
                            }
                        }
                    }
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
    }
}

private func makePipeline() -> ImagePipeline {
    struct MockDecoder: ImageDecoding {
        static let container = ImageContainer(image: Test.image)

        func decode(_ data: Data) throws -> ImageContainer {
            MockDecoder.container
        }
    }

    final class MockDataLoader: DataLoading {
        let response = (Test.data, URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 22789, textEncodingName: nil))

        func loadData(for request: URLRequest) -> AsyncThrowingStream<(Data, URLResponse), any Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(response)
                continuation.finish()
            }
        }
    }

    let pipeline = ImagePipeline {
        $0.imageCache = nil

        $0.dataLoader = MockDataLoader()

        $0.isDecompressionEnabled = false

        // This must be off for this test, because rate limiter is optimized for
        // the actual loading in the apps and not the synthetic tests like this.
        $0.isRateLimiterEnabled = false

        // Remove decoding from the equation
        $0.makeImageDecoder = { _ in ImageDecoders.Empty() }
    }

    return pipeline
}
