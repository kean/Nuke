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

    private final class MockOperation: @unchecked Sendable {
        private(set) var executeCalls = 0

        func execute() async -> Data {
            executeCalls += 1
            await Task.yield()
            return Test.data
        }
    }
}
