// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite struct DataRequestTests {
    @Test func initDoesNotStartExecutionRightAway() async throws {
        let operation = MockOperation()
        let pipeline = ImagePipeline()

        // Creating the request should NOT trigger the closure
        let request = ImageRequest(id: UUID().uuidString, data: {
            await operation.execute()
        })

        #expect(operation.executeCalls == 0)

        // Loading the image should trigger the closure
        _ = try await pipeline.image(for: request)

        #expect(operation.executeCalls == 1)
    }

    @Test func dataRequestDeliversCorrectImage() async throws {
        // GIVEN a request that provides image data via a closure
        let pipeline = ImagePipeline()
        let request = ImageRequest(id: "test-image", data: {
            Test.data
        })

        // WHEN
        let image = try await pipeline.image(for: request)

        // THEN the decoded image has the expected size
        #expect(image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    @Test func dataRequestThrowingClosurePropagatesError() async throws {
        // GIVEN a request whose data closure throws
        struct DataFetchError: Error {}
        let pipeline = ImagePipeline()
        let request = ImageRequest(id: "failing", data: {
            throw DataFetchError()
        })

        // WHEN / THEN the error is wrapped in a pipeline dataLoadingFailed error
        do {
            _ = try await pipeline.image(for: request)
            Issue.record("Expected an error")
        } catch {
            guard case .dataLoadingFailed = error else {
                Issue.record("Expected dataLoadingFailed, got \(error)")
                return
            }
        }
    }

    private final class MockOperation: @unchecked Sendable {
        private(set) var executeCalls = 0

        func execute() async -> Data {
            executeCalls += 1
            await Task.yield()
            return Test.data
        }
    }
}
