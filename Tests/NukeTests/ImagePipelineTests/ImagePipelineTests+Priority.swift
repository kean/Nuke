// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation

@testable import Nuke

extension ImagePipelineTests {
    @Test func updatedDataLoadingQueuePriority() async {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = Test.request
        #expect(request.priority == .normal)

        // When
        let expectation = queue.expectOperationAdded()
        let imageTask = pipeline.imageTask(with: request)
        Task {
            try await imageTask.response
        }
        let operation = await expectation.value

        // Then
        #expect(operation.priority == .normal)

        let expectation2 = queue.expectPriorityUpdated(for: operation)
        imageTask.priority = .high
        let newPriority = await expectation2.wait()

        #expect(newPriority == .high)
        #expect(operation.priority == .high)
    }

    @Test func updateDecodingPriority() async {
        // Given
        pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in MockImageDecoder(name: "test") }
        }

        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        let request = Test.request
        #expect(request.priority == .normal)

        let expectation = queue.expectOperationAdded()
        let task = pipeline.loadImage(with: request) { _ in }
        let operation = await expectation.value

        // When
        let expectation2 = queue.expectPriorityUpdated(for: operation)
        task.priority = .high

        // Then
        let newPriority = await expectation2.wait()
        #expect(newPriority == .high)
    }

    @Test func updateProcessingPriority() async {
        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        let request = ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "1", { $0 })])
        #expect(request.priority == .normal)

        let expectation = queue.expectOperationAdded()
        let task = pipeline.loadImage(with: request) { _ in }
        let operation = await expectation.value

        // When
        let expectation2 = queue.expectPriorityUpdated(for: operation)
        task.priority = .high

        // Then
        let newPriority = await expectation2.wait()
        #expect(newPriority == .high)
    }
}
