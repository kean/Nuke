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
    func asyncAwaitPerformanceWithChunkedResponse() async {
        // The transport decides how a response is sliced; a real download
        // rarely arrives in one piece.
        let pipeline = makePipeline {
            let dataLoader = MockDataLoader()
            dataLoader.chunkCount = 16
            $0.dataLoader = dataLoader
        }
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
    func asyncAwaitPerformanceWithDiagnostics() async {
        let pipeline = makePipeline { $0.isDiagnosticsEnabled = true }
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
    func memoryHitPerformance() async {
        let pipeline = makePipeline { $0.imageCache = ImageCache() }
        let requests = (0..<5000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")) }
        let container = Test.container
        for request in requests {
            pipeline.cache[request] = container
        }
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
    func memoryHitPerformanceWithDiagnostics() async {
        let pipeline = makePipeline {
            $0.imageCache = ImageCache()
            $0.isDiagnosticsEnabled = true
        }
        let requests = (0..<5000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")) }
        let container = Test.container
        for request in requests {
            pipeline.cache[request] = container
        }
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

private func makePipeline(_ configure: (inout ImagePipeline.Configuration) -> Void = { _ in }) -> ImagePipeline {
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

        configure(&$0)
    }

    return pipeline
}
