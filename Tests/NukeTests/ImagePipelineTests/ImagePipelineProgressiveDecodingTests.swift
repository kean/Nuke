// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(1)))
struct ImagePipelineProgressiveDecodingTests {
    private let dataLoader: MockProgressiveDataLoader
    private let pipeline: ImagePipeline
    private let cache: MockImageCache
    private let processorsFactory: MockProcessorFactory

    init() {
        let dataLoader = MockProgressiveDataLoader()

        let cache = MockImageCache()
        let processorsFactory = MockProcessorFactory()

        self.dataLoader = dataLoader
        self.cache = cache
        self.processorsFactory = processorsFactory

        // We make two important assumptions with this setup:
        //
        // 1. Image processing is serial which means that all partial images are
        // going to be processed and sent to the client before the final image is
        // processed. So there's never going to be a situation where the final
        // image is processed before one of the partial images.
        //
        // 2. Each data chunk produced by a data loader always results in a new
        // scan. The way we split the data guarantees that.

        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
            $0.isProgressiveDecodingEnabled = true
            $0.isStoringPreviewsInMemoryCache = true
            $0.progressiveDecodingInterval = 0
            $0.imageProcessingQueue = TaskQueue(maxConcurrentOperationCount: 1)
        }
    }

    // MARK: - Basics

    @Test func progressiveDecoding() async throws {
        // Given
        // - An image which supports progressive decoding
        // - A pipeline with progressive decoding enabled

        // When
        var recordedPreviews: [ImageResponse] = []
        let task = pipeline.imageTask(with: Test.request)
        for try await preview in task.previews {
            // Then image previews are produced
            #expect(preview.container.isPreview)

            // Then the preview is stored in memory cache
            let cached = cache[Test.request]
            #expect(cached != nil)
            #expect(cached?.isPreview == true)
            #expect(cached?.image == preview.container.image)

            recordedPreviews.append(preview)
            dataLoader.resume()
        }
        let response = try await task.response

        // Then two scans are produced
        #expect(recordedPreviews.count == 2)

        // Then the final image is produced
        #expect(!response.container.isPreview)

        // Then the preview is overwritten with the final image in memory cache
        let cached = cache[Test.request]
        #expect(cached != nil)
        #expect(cached?.isPreview == false)
        #expect(cached?.image == response.image)
    }

    @Test func failedPartialImagesAreIgnored() async throws {
        // Given
        class FailingPartialsDecoder: ImageDecoding, @unchecked Sendable {
            func decode(_ data: Data) throws -> ImageContainer {
                try ImageDecoders.Default().decode(data)
            }
        }

        let registry = ImageDecoderRegistry()
        registry.register { _ in
            FailingPartialsDecoder()
        }

        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { registry.decoder(for: $0) }
        }

        // When/Then
        let task = pipeline.imageTask(with: Test.request)

        // Subscribe to both streams synchronously before suspending to avoid a
        // race where the background task starts too late and misses the first
        // progress event (which is served automatically on the main queue).
        let dataLoader = self.dataLoader
        let progressEvents = task.progress
        let previewEvents = task.previews

        Task {
            for await _ in progressEvents {
                dataLoader.resume()
            }
        }

        var recordedPreviews: [ImageResponse] = []
        for try await preview in previewEvents {
            recordedPreviews.append(preview)
            dataLoader.resume()
        }
        let response = try await task.response

        // Then partial images are never produced
        #expect(recordedPreviews.isEmpty)
        // Then the final image is produced
        #expect(!response.isPreview)
    }

    // MARK: - Image Processing

#if !os(macOS)
    @Test func partialImagesAreResized() async throws {
        // Given
        let image = PlatformImage(data: dataLoader.data)
        #expect(image?.cgImage?.width == 450)
        #expect(image?.cgImage?.height == 300)

        let request = ImageRequest(
            url: Test.url,
            processors: [ImageProcessors.Resize(size: CGSize(width: 45, height: 30), unit: .pixels)]
        )

        // When
        var recordedPreviews: [ImageResponse] = []
        let task = pipeline.imageTask(with: request)
        for try await preview in task.previews {
            #expect(preview.image.cgImage?.width == 45)
            #expect(preview.image.cgImage?.height == 30)
            recordedPreviews.append(preview)
            dataLoader.resume()
        }
        let response = try await task.response

        // Then
        #expect(recordedPreviews.count == 2)
        #expect(response.image.cgImage?.width == 45)
        #expect(response.image.cgImage?.height == 30)
    }
#endif

    @Test func partialImagesAreProcessed() async throws {
        // Given
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "_image_processor")])

        // When
        var recordedPreviews: [ImageResponse] = []
        let task = pipeline.imageTask(with: request)
        for try await preview in task.previews {
            #expect(preview.image.nk_test_processorIDs.count == 1)
            #expect(preview.image.nk_test_processorIDs.first == "_image_processor")
            recordedPreviews.append(preview)
            dataLoader.resume()
        }
        let response = try await task.response

        // Then
        #expect(recordedPreviews.count == 2)
        #expect(response.image.nk_test_processorIDs.count == 1)
        #expect(response.image.nk_test_processorIDs.first == "_image_processor")
    }

    @Test func progressiveDecodingDisabled() async throws {
        // Given
        var configuration = pipeline.configuration
        configuration.isProgressiveDecodingEnabled = false
        let pipeline = ImagePipeline(configuration: configuration)

        // When
        let task = pipeline.imageTask(with: Test.request)

        // Subscribe to both streams synchronously before suspending to avoid a
        // race where the background task starts too late and misses the first
        // progress event (which is served automatically on the main queue).
        let dataLoader = self.dataLoader
        let progressEvents = task.progress
        let previewEvents = task.previews
        Task {
            for await _ in progressEvents {
                dataLoader.resume()
            }
        }

        var recordedPreviews: [ImageResponse] = []
        for try await preview in previewEvents {
            recordedPreviews.append(preview)
            dataLoader.resume()
        }
        let response = try await task.response

        // Then partial images are never produced
        #expect(recordedPreviews.isEmpty)
        #expect(!response.isPreview)
    }

    // MARK: Back Pressure

    @Test @ImagePipelineActor func backpressureImageDecoding() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in MockImageDecoder(name: "a") }
        }

        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        let dataLoader = dataLoader
        let expectation = TestExpectation(queue: queue, count: 2)
        let task = pipeline.imageTask(with: ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "1", { $0 })]))
        let previewEvents = task.previews
        let progressEvents = task.progress
        Task {
            for try await _ in previewEvents {
                dataLoader.resume()
            }
        }
        Task {
            for await _ in progressEvents {
                dataLoader.resume()
            }
        }
        await expectation.wait()

        // Then only 2 operations: 1 partial, 1 final
        #expect(expectation.operations.count == 2)

        queue.isSuspended = false
        let response = try await task.response
        #expect(!response.isPreview)
    }

    // MARK: Memory Cache

    @Test func intermediateMemoryCachedResultsAreDelivered() async throws {
        // GIVEN intermediate result stored in memory cache
        let request = ImageRequest(url: Test.url, processors: [
            processorsFactory.make(id: "1"),
            processorsFactory.make(id: "2")
        ])
        let intermediateRequest = ImageRequest(url: Test.url, processors: [
            processorsFactory.make(id: "1")
        ])
        cache[intermediateRequest] = ImageContainer(image: Test.image, isPreview: true)

        pipeline.configuration.dataLoadingQueue.isSuspended = true // Make sure no data is loaded

        // WHEN/THEN the pipeline finds the first preview in the memory cache,
        // applies the remaining processors and delivers it
        let task = pipeline.imageTask(with: request)
        var recordedPreviews: [ImageResponse] = []
        for try await preview in task.previews {
            recordedPreviews.append(preview)
            break // Only need the first preview; data loading is suspended
        }

        #expect(recordedPreviews.count == 1)
        #expect(recordedPreviews.first?.image.nk_test_processorIDs == ["2"])
        #expect(recordedPreviews.first?.container.isPreview == true)
    }

    // MARK: - Cancellation

    @Test func cancelBeforeLoadingStartedIsHandledGracefully() async {
        // GIVEN a task that is cancelled synchronously before the response is awaited
        let task = pipeline.imageTask(with: Test.request)
        task.cancel()

        // THEN awaiting the response either throws (most likely) or succeeds
        // without crashing. We do NOT record a failure if it succeeds, since
        // timing means the loading may have already completed.
        _ = try? await task.response
    }

    // MARK: Scale

#if os(iOS) || os(visionOS)
    @Test func overridingImageScaleWithFloat() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url).with { $0.scale = 7.0 }

        // WHEN/THEN
        let task = pipeline.imageTask(with: request)
        var previewScale: CGFloat?
        for try await preview in task.previews {
            previewScale = preview.image.scale
            dataLoader.resume()
        }
        _ = try await task.response

        #expect(previewScale == 7)
    }
#endif
}
