// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Nuke

@Suite(.serialized)
@MainActor
struct ImagePipelinePerformanceTests {
    @Test
    func asyncAwaitPerformance() async {
        let pipeline = makePipeline()
        let requests = (0..<5000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")) }
        await measure {
            await withTaskGroup(of: Void.self) { group in
                for request in requests {
                    group.addTask {
                        _ = try? await pipeline.image(for: request)
                    }
                }
            }
        }
    }

    @Test
    func asyncImageTaskPerformance() async {
        let pipeline = makePipeline()
        let requests = (0..<5000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")) }
        await measure {
            await withTaskGroup(of: Void.self) { group in
                for request in requests {
                    group.addTask {
                        _ = try? await pipeline.imageTask(with: request).image
                    }
                }
            }
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
