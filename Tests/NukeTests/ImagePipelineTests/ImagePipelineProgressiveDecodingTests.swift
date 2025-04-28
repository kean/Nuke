// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

@ImagePipelineActor
@Suite class ImagePipelineProgressiveDecodingTests {
    private var dataLoader: MockProgressiveDataLoader!
    private var pipeline: ImagePipeline!
    private var cache: MockImageCache!
    private var processorsFactory: MockProcessorFactory!

    init() {
        dataLoader = MockProgressiveDataLoader()
        ResumableDataStorage.shared.removeAllResponses()

        cache = MockImageCache()
        processorsFactory = MockProcessorFactory()

        // We make two important assumptions with this setup:
        //
        // 1. Image processing is serial which means that all partial images are
        // going to be processed and sent to the client before the final image is
        // processed. So there's never going to be a situation where the final
        // image is processed before one of the partial images.
        //
        // 2. Each data chunk produced by a data loader always results in a new
        // scan. The way we split the data guarantees that.

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
            $0.isProgressiveDecodingEnabled = true
            $0.isStoringPreviewsInMemoryCache = true
            $0.imageProcessingQueue.maxConcurrentJobCount = 1
        }
    }

    @Test func testProgressDecoding() async throws {
        // Given
        let imageTask = pipeline.imageTask(with: Test.request)

        // When
        var previewCount = 0
        for try await preview in imageTask.previews {
            // Then image previews are produced
            #expect(preview.isPreview)

            // Then the preview is stored in memory cache
            let cached = try #require(cache[Test.request])
            #expect(cached.isPreview)
            #expect(cached.image == preview.image)

            previewCount += 1
            dataLoader.resume()
        }

        // Then two previws are received
        #expect(previewCount == 2)

        // When
        let response = try await imageTask.response

        // Then
        #expect(!response.container.isPreview)

        let cached = try #require(cache[Test.request])
        #expect(!cached.isPreview)
        #expect(cached.image == response.image)
    }

    @Test func thatFailedPartialImagesAreIgnored() async {
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

        pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { registry.decoder(for: $0) }
        }

        // When
        let imageTask = pipeline.imageTask(with: Test.request)

        // Then
        for await event in imageTask.events {
            switch event {
            case .progress:
                dataLoader.resume()
            case .preview:
                Issue.record("Expected partial images to never be produced")
            case .cancelled:
                Issue.record()
            case .finished(let result):
                #expect(result.isSuccess, "Expected the final image to be produced")
            }
        }
    }

    // MARK: - Image Processing

#if !os(macOS)
    @Test func thatPartialImagesAreResized() async {
        // Given
        let image = PlatformImage(data: dataLoader.data)
        #expect(image?.cgImage?.width == 450)
        #expect(image?.cgImage?.height == 300)

        let request = ImageRequest(
            url: Test.url,
            processors: [ImageProcessors.Resize(size: CGSize(width: 45, height: 30), unit: .pixels)]
        )

        // When
        let imageTask = pipeline.imageTask(with: request)
        for await event in imageTask.events {
            switch event {
            case .progress:
                dataLoader.resume()
            case .preview(let response):
                // Then previews are resized
                #expect(response.isPreview)
                #expect(response.image.cgImage?.width == 45)
                #expect(response.image.cgImage?.height == 30)
            case .cancelled:
                Issue.record()
            case .finished(let result):
                switch result {
                case .success(let response):
                    // Then the final image is also resized
                    #expect(!response.isPreview)
                    #expect(response.image.cgImage?.width == 45)
                    #expect(response.image.cgImage?.height == 30)
                case .failure:
                    Issue.record()
                }
                #expect(result.isSuccess, "Expected the final image to be produced")
            }
        }
    }
#endif

    @Test func thatPartialImagesAreProcessed() async {
        // Given
        let request = ImageRequest(url: Test.url, processors: [
            MockImageProcessor(id: "_image_processor")]
        )

        // When/Then
        let imageTask = pipeline.imageTask(with: request)
        for await event in imageTask.events {
            switch event {
            case .progress:
                dataLoader.resume()
            case .preview(let response):
                // Then previews are resized
                #expect(response.isPreview)
                #expect(response.image.nk_test_processorIDs == ["_image_processor"])
            case .cancelled:
                Issue.record()
            case .finished(let result):
                switch result {
                case .success(let response):
                    // Then the final image is also resized
                    #expect(!response.isPreview)
                    #expect(response.image.nk_test_processorIDs == ["_image_processor"])
                case .failure:
                    Issue.record()
                }
            }
        }
    }

    @Test func progressiveDecodingDisabled() async {
        // Given
        var configuration = pipeline.configuration
        configuration.isProgressiveDecodingEnabled = false
        pipeline = ImagePipeline(configuration: configuration)

        // When/Then
        let imageTask = pipeline.imageTask(with: Test.request)
        for await event in imageTask.events {
            switch event {
            case .progress:
                dataLoader.resume()
            case .preview:
                Issue.record("No previwes should be produced")
            case .cancelled:
                Issue.record()
            case .finished(let result):
                switch result {
                case .success(let response):
                    // Then the final image is also resized
                    #expect(!response.isPreview)
                case .failure:
                    Issue.record()
                }
            }
        }
    }

    // MARK: Back Pressure

    @Test func backpressureImageDecoding() async throws {
        pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in MockImageDecoder(name: "a") }
        }

        // Given
        let decodingQueue = pipeline.configuration.imageDecodingQueue
        decodingQueue.isSuspended = true

        // When the first chunk is delivered
        // Then the first processing operation is enqueue
        let expectationDecodingStarted = decodingQueue.expectJobAdded()
        let expectationImageLoaded = AsyncExpectation<ImageResponse>()

        Task { @ImagePipelineActor in
            do {
                let response = try await pipeline.imageTask(with: Test.request).response
                expectationImageLoaded.fulfill(with: response)
            } catch {
                Issue.record(error)
            }
        }

        let firstDecodingTask = await expectationDecodingStarted.wait()

        // When the second chunk is delivered
        dataLoader.serveNextChunk()

        let expectationPreviewDecodingCancelled = decodingQueue.expectJobCancelled(firstDecodingTask)

        // When the last chunk is delivered the
        dataLoader.serveNextChunk()

        // Then the preview processing task gets cancelled
        _ = await expectationPreviewDecodingCancelled.wait()

        // When processing is resumed
        decodingQueue.isSuspended = false

        // Then final image is loaded and other expectation are met
        let response = await expectationImageLoaded.wait()
        #expect(!response.isPreview)
    }

    @Test func backpressureImageProcessing() async throws {
        // Given
        let processingQueue = pipeline.configuration.imageProcessingQueue
        processingQueue.isSuspended = true

        // Given a request with a processor
        let request = ImageRequest(
            url: Test.url,
            processors: [ImageProcessors.Anonymous(id: "1", { $0 })]
        )

        // When the first chunk is delivered
        // Then the first processing operation is enqueue
        let expectationProcessingStarted = processingQueue.expectJobAdded()
        let expectationImageLoaded = AsyncExpectation<ImageResponse>()

        Task { @ImagePipelineActor in
            do {
                let response = try await pipeline.imageTask(with: request).response
                expectationImageLoaded.fulfill(with: response)
            } catch {
                Issue.record(error)
            }
        }

        let firstProcessingJob = await expectationProcessingStarted.wait()

        // When the second chunk is delivered
        dataLoader.serveNextChunk()

        let expectationPreviewProcessingCancelled = processingQueue.expectJobCancelled(firstProcessingJob)

        // When the last chunk is delivered the
        dataLoader.serveNextChunk()

        // Then the preview processing task gets cancelled
        _ = await expectationPreviewProcessingCancelled.wait()

        // When processing is resumed
        processingQueue.isSuspended = false

        // Then final image is loaded and other expectation are met
        let response = await expectationImageLoaded.wait()
        #expect(!response.isPreview)
    }

    // MARK: Scale

#if os(iOS) || os(visionOS)
    @Test func overridingImageScaleWithFloat() async {
        // Given
        let request = ImageRequest(url: Test.url, userInfo: [.scaleKey: 7.0])

        // When/Then the pipeline find the first preview in the memory cache,
        // applies the remaining processors and delivers it
        let previewDelivered = AsyncExpectation<Void>()
        pipeline.loadImage(with: request) { response, _, _ in
            guard let response else {
                return
            }
            #expect(response.container.isPreview)
            #expect(response.image.scale == 7)
            previewDelivered.fulfill()
        } completion: { _ in
            // Do nothing
        }
        await previewDelivered.wait()
    }
#endif

    // MARK: - Callbacks

    // Very basic test, just make sure that partial images get produced and
    // that the completion handler is called at the end.
    @Test func callbacksProgressiveDecoding() async {
        // Given
        // - An image which supports progressive decoding
        // - A pipeline with progressive decoding enabled

        // Then two scans are produced
        let expectPartialImageProduced = AsyncExpectation<Void>()
        let previewCount = Mutex(wrappedValue: 0)

        // Then the final image is produced
        let expectFinalImageProduced = AsyncExpectation<Void>()

        // When
        pipeline.loadImage(
            with: Test.request,
            progress: { [cache, dataLoader] response, _, _ in
                // This works because each new chunk resulted in a new scan
                if let container = response?.container {
                    // Then image previews are produced
                    #expect(container.isPreview)

                    // Then the preview is stored in memory cache
                    let cached = cache?[Test.request]
                    #expect(cached != nil)
                    #expect(cached?.isPreview ?? false)
                    #expect(cached?.image == container.image)

                    let count = previewCount.withLock {
                        $0 += 1
                        return $0
                    }
                    if count == 2 {
                        expectPartialImageProduced.fulfill()
                    } else if count > 2 {
                        Issue.record()
                    }
                    dataLoader?.resume()
                }
            },
            completion: { [cache] result in
                // Then the final image is produced
                switch result {
                case let .success(response):
                    #expect(!response.container.isPreview)
                case .failure:
                    Issue.record("Unexpected failure")
                }

                // Then the preview is overwritted with the final image in memory cache
                let cached = cache?[Test.request]
                #expect(cached != nil)
                #expect(!(cached?.isPreview ?? false))
                #expect(cached?.image == result.value?.image)

                expectFinalImageProduced.fulfill()
            }
        )

        await expectPartialImageProduced.wait()
        await expectFinalImageProduced.wait()
    }
}
