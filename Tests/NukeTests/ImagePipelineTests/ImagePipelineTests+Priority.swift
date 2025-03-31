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
        let expectation = queue.expectItemAdded()
        let imageTask = pipeline.imageTask(with: request)
        Task {
            try await imageTask.response
        }
        let workItem = await expectation.wait()

        // Then
        #expect(workItem.priority == .normal)

        let expectation2 = queue.expectPriorityUpdated(for: workItem)
        imageTask.priority = .high
        let newPriority = await expectation2.wait()

        #expect(newPriority == .high)
        #expect(workItem.priority == .high)
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

        let expectation = queue.expectItemAdded()
        let task = pipeline.loadImage(with: request) { _ in }
        let workItem = await expectation.wait()

        // When
        let expectation2 = queue.expectPriorityUpdated(for: workItem)
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

        let expectation = queue.expectItemAdded()
        let task = pipeline.loadImage(with: request) { _ in }
        let workItem = await expectation.wait()

        // When
        let expectation2 = queue.expectPriorityUpdated(for: workItem)
        task.priority = .high

        // Then
        let newPriority = await expectation2.wait()
        #expect(newPriority == .high)
    }
}
