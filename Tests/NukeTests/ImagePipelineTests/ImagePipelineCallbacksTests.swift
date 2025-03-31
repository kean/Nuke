// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Combine
import Foundation

@testable import Nuke

@ImagePipelineActor
@Suite class ImagePipelineCallbacksTests {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    init() {
        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Completion

    @Test func completionCalledOnMainThread() async throws {
        let response = try await withCheckedThrowingContinuation { continuation in
            pipeline.loadImage(with: Test.request) { result in
                #expect(Thread.isMainThread)
                continuation.resume(with: result)
            }
        }
        #expect(response.image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    // MARK: - Progress

    @Test func taskProgressIsUpdated() async {
        // Given
        let request = ImageRequest(url: Test.url)

        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let recordedProgress = Mutex<[ImageTask.Progress]>(wrappedValue: [])
        await withCheckedContinuation { continuation in
            pipeline.loadImage(
                with: request,
                progress: { _, completed, total in
                    // Then
                    #expect(Thread.isMainThread)
                    recordedProgress.withLock {
                        $0.append(ImageTask.Progress(completed: completed, total: total))
                    }
                },
                completion: { _ in
                    continuation.resume()
                }
            )
        }

        // Then
        #expect(recordedProgress.wrappedValue == [
            ImageTask.Progress(completed: 10, total: 20),
            ImageTask.Progress(completed: 20, total: 20)
        ])
    }
}

//
//    // MARK: - Invalidate
//
//    @Test func whenInvalidatedTasksAreCancelled() {
//        dataLoader.queue.isSuspended = true
//
//        expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
//        pipeline.loadImage(with: Test.request) { _ in
//            Issue.record()
//        }
//        wait() // Wait till operation is created
//
//        expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
//        pipeline.invalidate()
//        wait()
//    }
//
//    @Test func thatInvalidatedTasksFailWithError() async throws {
//        // When
//        pipeline.invalidate()
//
//        // Then
//        do {
//            _ = try await pipeline.image(for: Test.request)
//            Issue.record()
//        } catch {
//            #expect(error as? ImagePipeline.Error == .pipelineInvalidated)
//        }
//    }
//
//    // MARK: Error Handling
//
//    @Test func dataLoadingFailedErrorReturned() {
//        // Given
//        let dataLoader = MockDataLoader()
//        let pipeline = ImagePipeline {
//            $0.dataLoader = dataLoader
//            $0.imageCache = nil
//        }
//
//        let expectedError = NSError(domain: "t", code: 23, userInfo: nil)
//        dataLoader.results[Test.url] = .failure(expectedError)
//
//        // When/Then
//        expect(pipeline).toFailRequest(Test.request, with: .dataLoadingFailed(error: expectedError))
//        wait()
//    }
//
//    @Test func dataLoaderReturnsEmptyData() {
//        // Given
//        let dataLoader = MockDataLoader()
//        let pipeline = ImagePipeline {
//            $0.dataLoader = dataLoader
//            $0.imageCache = nil
//        }
//
//        dataLoader.results[Test.url] = .success((Data(), Test.urlResponse))
//
//        // When/Then
//        expect(pipeline).toFailRequest(Test.request, with: .dataIsEmpty)
//        wait()
//    }
//
//    @Test func decoderNotRegistered() {
//        // Given
//        let pipeline = ImagePipeline {
//            $0.dataLoader = MockDataLoader()
//            $0.makeImageDecoder = { _ in
//                nil
//            }
//            $0.imageCache = nil
//        }
//
//        expect(pipeline).toFailRequest(Test.request) { result in
//            guard let error = result.error else {
//                return Issue.record("Expected error")
//            }
//            guard case let .decoderNotRegistered(context) = error else {
//                return Issue.record("Expected .decoderNotRegistered")
//            }
//            #expect(context.request.url == Test.request.url)
//            #expect(context.data.count == 22789)
//            #expect(context.isCompleted)
//            #expect(context.urlResponse?.url == Test.url)
//        }
//        wait()
//    }
//
//    @Test func decodingFailedErrorReturned() async {
//        // Given
//        let decoder = MockFailingDecoder()
//        let pipeline = ImagePipeline {
//            $0.dataLoader = MockDataLoader()
//            $0.makeImageDecoder = { _ in decoder }
//            $0.imageCache = nil
//        }
//
//        // When/Then
//        do {
//            _ = try await pipeline.image(for: Test.request)
//            Issue.record("Expected failure")
//        } catch {
//            if case let .decodingFailed(failedDecoder, context, error) = error as? ImagePipeline.Error {
//                #expect((failedDecoder as? MockFailingDecoder) === decoder)
//
//                #expect(context.request.url == Test.request.url)
//                #expect(context.data == Test.data)
//                #expect(context.isCompleted)
//                #expect(context.urlResponse?.url == Test.url)
//
//                #expect(error as? MockError == MockError(description: "decoder-failed"))
//            } else {
//                Issue.record("Unexpected error: \(error)")
//            }
//        }
//    }
//
//    @Test func processingFailedErrorReturned() {
//        // Given
//        let pipeline = ImagePipeline {
//            $0.dataLoader = MockDataLoader()
//        }
//
//        let request = ImageRequest(url: Test.url, processors: [MockFailingProcessor()])
//
//        // When/Then
//        expect(pipeline).toFailRequest(request) { result in
//            guard case .failure(let error) = result,
//                  case let .processingFailed(processor, context, error) = error else {
//                return Issue.record()
//            }
//
//            #expect(processor is MockFailingProcessor)
//
//            #expect(context.request.url == Test.url)
//            #expect(context.response.container.image.sizeInPixels == CGSize(width: 640, height: 480))
//            #expect(context.response.cacheType == nil)
//            #expect(context.isCompleted == true)
//
//            #expect(error as? ImageProcessingError == .unknown)
//        }
//        wait()
//    }
//
//    @Test func imageContainerUserInfo() { // Just to make sure we have 100% coverage
//        // When
//        let container = ImageContainer(image: Test.image, type: nil, isPreview: false, data: nil, userInfo: [.init("a"): 1])
//
//        // Then
//        #expect(container.userInfo["a"] as? Int == 1)
//    }
//
//    @Test func errorDescription() {
//        #expect(!ImagePipeline.Error.dataLoadingFailed(error: URLError(.unknown)).description.isEmpty) // Just padding here // Just padding here
//
//        #expect(!ImagePipeline.Error.decodingFailed(decoder: MockImageDecoder(name: "test"), context: .mock, error: MockError(description: "decoding-failed")).description.isEmpty) // Just padding // Just padding
//
//        let processor = ImageProcessors.Resize(width: 100, unit: .pixels)
//        let error = ImagePipeline.Error.processingFailed(processor: processor, context: .mock, error: MockError(description: "processing-failed"))
//        let expected = "Failed to process the image using processor Resize(size: (100.0, 9999.0) pixels, contentMode: .aspectFit, crop: false, upscale: false). Underlying error: MockError(description: \"processing-failed\")."
//        #expect(error.description == expected)
//        #expect("\(error)" == expected)
//
//        #expect(error.dataLoadingError == nil)
//    }
//
//    // MARK: Skip Data Loading Queue Option
//
//    @Test func skipDataLoadingQueuePerRequestWithURL() throws {
//        // Given
//        let queue = pipeline.configuration.dataLoadingQueue
//        queue.isSuspended = true
//
//        let request = ImageRequest(url: Test.url, options: [
//            .skipDataLoadingQueue
//        ])
//
//        // Then image is still loaded
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//    }
//
//    // MARK: Misc
//
//    @Test func loadWithStringLiteral() async throws {
//        let image = try await pipeline.image(for: "https://example.com/image.jpeg")
//        #expect(image.size != .zero)
//    }
//
//    @Test func loadWithInvalidURL() throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataLoader = DataLoader()
//        }
//
//        // When
//        for _ in 0...10 {
//            expect(pipeline).toFailRequest(ImageRequest(url: URL(string: "")))
//            wait()
//        }
//    }
//
//#if !os(macOS)
//    @Test func overridingImageScale() throws {
//        // Given
//        let request = ImageRequest(url: Test.url, userInfo: [.scaleKey: 7])
//
//        // When
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then
//        let image = try #require(record.image)
//        #expect(image.scale == 7)
//    }
//
//    @Test func overridingImageScaleWithFloat() throws {
//        // Given
//        let request = ImageRequest(url: Test.url, userInfo: [.scaleKey: 7.0])
//
//        // When
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then
//        let image = try #require(record.image)
//        #expect(image.scale == 7)
//    }
//#endif
//}
