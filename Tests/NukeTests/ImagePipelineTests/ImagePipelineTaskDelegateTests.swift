// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite struct ImagePipelineTaskDelegateTests {
    private let dataLoader: MockDataLoader
    private let pipeline: ImagePipeline
    private let delegate: ImagePipelineObserver

    init() {
        let dataLoader = MockDataLoader()
        let delegate = ImagePipelineObserver()
        self.dataLoader = dataLoader
        self.delegate = delegate
        self.pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    @Test func startAndCompletedEvents() async throws {
        let completed = TestExpectation(notification: ImagePipelineObserver.didCompleteTask, object: delegate)
        let response = try await pipeline.imageTask(with: Test.request).response
        await completed.wait()

        // Then
        #expect(delegate.events == [
            ImageTaskEvent.created,
            .started,
            .progressUpdated(completedUnitCount: 22789, totalUnitCount: 22789),
            .completed(result: .success(response))
        ])
    }

    @Test func progressUpdateEvents() async throws {
        let request = ImageRequest(url: Test.url)
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        let completed = TestExpectation(notification: ImagePipelineObserver.didCompleteTask, object: delegate)
        var result: Result<ImageResponse, ImagePipeline.Error>?
        do {
            let response = try await pipeline.imageTask(with: request).response
            result = .success(response)
        } catch {
            result = .failure(error)
        }
        await completed.wait()

        // Then
        #expect(delegate.events == [
            ImageTaskEvent.created,
            .started,
            .progressUpdated(completedUnitCount: 10, totalUnitCount: 20),
            .progressUpdated(completedUnitCount: 20, totalUnitCount: 20),
            .completed(result: try #require(result))
        ])
    }

    @Test func cancellationEvents() async {
        dataLoader.queue.isSuspended = true

        let startExpectation = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.imageTask(with: Test.request)
        Task.detached { try? await task.response }
        await startExpectation.wait()

        await notification(ImagePipelineObserver.didCancelTask, object: delegate) {
            task.cancel()
        }
        await Task.yield()

        // Then
        #expect(delegate.events == [
            ImageTaskEvent.created,
            .started,
            .cancelled
        ])
    }
}
