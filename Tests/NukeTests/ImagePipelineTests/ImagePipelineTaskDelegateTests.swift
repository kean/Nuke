// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

@Suite struct ImagePipelineTaskDelegateTests {
    private var dataLoader: MockDataLoader!
    private var pipeline: ImagePipeline!
    private var delegate: ImagePipelineObserver!

    init() {
        dataLoader = MockDataLoader()
        delegate = ImagePipelineObserver()

        pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    @Test func startAndCompletedEvents() async throws {
        let result = await Task {
            try await pipeline.imageTask(with: Test.url).response
        }.result.mapError { $0 as! ImageTask.Error }

        // Then
        #expect(delegate.events == [
            .progress(.init(completed: 22789, total: 22789)),
            .finished(result)
        ])
    }

    @Test func progressUpdateEvents() async throws {
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        let result = await Task {
            try await pipeline.imageTask(with: Test.url).response
        }.result.mapError { $0 as! ImageTask.Error }

        // Then
        #expect(delegate.events == [
            .progress(.init(completed: 10, total: 20)),
            .progress(.init(completed: 20, total: 20)),
            .finished(result)
        ])
    }

    @Test func cancellationEvents() async throws {
        dataLoader.queue.isSuspended = true

        let expectation1 = AsyncExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.imageTask(with: Test.request).resume()
        await expectation1.wait()

        // When
        let expectation2 = AsyncExpectation(notification: ImagePipelineObserver.didCancelTask, object: delegate)
        task.cancel()
        await expectation2.wait()

        // Then
        #expect(delegate.events == [
            .cancelled
        ])
    }
}
