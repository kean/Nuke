@testable import Nuke
import XCTest

@available(iOS 18.0, *)
class OnQueueTaskExecuterTests: XCTestCase {
    func testThatTasksRunsOnQueue() async {
        // Given
        let queue = DispatchQueue(label: "task.queue")
        let executor = OnQueueTaskExecuter(queue: queue)
        let expectation = self.expectation(description: "All work executed")

        // When, Then
        Task(executorPreference: executor) {
            dispatchPrecondition(condition: .onQueue(queue))
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 0.1)
    }
}
