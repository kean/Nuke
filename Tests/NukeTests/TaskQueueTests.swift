// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite @ImagePipelineActor struct TaskQueueTests {
    // MARK: - Basic Execution

    @Test func addedWorkIsExecuted() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let executed = Ref(false)

        // When
        queue.add { executed.value = true }
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(executed.value)
    }

    @Test func multipleWorkItemsAllComplete() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let count = Ref(0)

        // When
        queue.add { count.value += 1 }
        queue.add { count.value += 1 }
        queue.add { count.value += 1 }
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(count.value == 3)
    }

    @Test func addReturnsTaskQueueOperation() {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)

        // When
        let operation = queue.add { }

        // Then
        #expect(!operation.isCancelled)
    }

    // MARK: - Concurrency Limit

    @Test func respectsmaxConcurrentTaskCountOfOne() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let item1Started = TestExpectation()
        let item2Started = Ref(false)
        let gate = TestExpectation()

        queue.add {
            item1Started.fulfill()
            await gate.wait()
        }
        queue.add {
            item2Started.value = true
        }

        // When – wait for item 1 to start
        await item1Started.wait()

        // Then – item 2 hasn't started because maxConcurrentTaskCount is 1
        #expect(!item2Started.value)

        // Cleanup – release item 1 so the queue drains
        gate.fulfill()
        await queue.waitUntilAllOperationsAreFinished()
        #expect(item2Started.value)
    }

    @Test func respectsmaxConcurrentTaskCountOfTwo() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 2)
        let item1Started = TestExpectation()
        let item2Started = TestExpectation()
        let item3Started = Ref(false)
        let gate1 = TestExpectation()
        let gate2 = TestExpectation()

        queue.add {
            item1Started.fulfill()
            await gate1.wait()
        }
        queue.add {
            item2Started.fulfill()
            await gate2.wait()
        }
        queue.add {
            item3Started.value = true
        }

        // When – wait for both slots to fill
        await item1Started.wait()
        await item2Started.wait()

        // Then – item 3 is blocked because both slots are occupied
        #expect(!item3Started.value)

        // Cleanup
        gate1.fulfill()
        gate2.fulfill()
        await queue.waitUntilAllOperationsAreFinished()
        #expect(item3Started.value)
    }

    @Test func increasingMaxConcurrentTaskCountDrainsPendingWork() async {
        // Given – capacity 1, two items: one running, one blocked
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let item1Started = TestExpectation()
        let item2Started = TestExpectation()
        let gate1 = TestExpectation()
        let gate2 = TestExpectation()

        queue.add {
            item1Started.fulfill()
            await gate1.wait()
        }
        queue.add {
            item2Started.fulfill()
            await gate2.wait()
        }

        await item1Started.wait()

        // When – increase capacity to 2
        queue.maxConcurrentTaskCount = 2

        // Then – item 2 starts immediately
        await item2Started.wait()

        // Cleanup
        gate1.fulfill()
        gate2.fulfill()
        await queue.waitUntilAllOperationsAreFinished()
    }

    @Test func decreasingMaxConcurrentTaskCountLetsRunningFinish() async {
        // Given – capacity 2, two items running
        let queue = TaskQueue(maxConcurrentTaskCount: 2)
        let item1Started = TestExpectation()
        let item2Started = TestExpectation()
        let item3Started = Ref(false)
        let gate1 = TestExpectation()
        let gate2 = TestExpectation()

        queue.add {
            item1Started.fulfill()
            await gate1.wait()
        }
        queue.add {
            item2Started.fulfill()
            await gate2.wait()
        }
        queue.add {
            item3Started.value = true
        }

        await item1Started.wait()
        await item2Started.wait()

        // When – reduce capacity to 1 while 2 are running
        queue.maxConcurrentTaskCount = 1

        // Then – both running items complete
        gate1.fulfill()
        gate2.fulfill()
        await queue.waitUntilAllOperationsAreFinished()

        // Item 3 also ran (after one of the first two finished, count dropped below limit)
        #expect(item3Started.value)
    }

    @Test func settingSameMaxConcurrentTaskCountDoesNotDrain() async {
        // Given – capacity 1, one item running, one pending
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let item1Started = TestExpectation()
        let item2Started = Ref(false)
        let gate = TestExpectation()

        queue.add {
            item1Started.fulfill()
            await gate.wait()
        }
        queue.add {
            item2Started.value = true
        }

        await item1Started.wait()

        // When – set to the same value
        queue.maxConcurrentTaskCount = 1

        // Then – no extra drain, item 2 still pending
        #expect(!item2Started.value)

        // Cleanup
        gate.fulfill()
        await queue.waitUntilAllOperationsAreFinished()
    }

    // MARK: - Priority

    @Test func highPriorityItemExecutesFirst() async {
        // Given – suspended queue so we can enqueue before any execute
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true

        let order = Ref<[String]>([])

        let lowOp = queue.add { order.value.append("low") }
        lowOp.priority = .low

        queue.add { order.value.append("normal") }

        let highOp = queue.add { order.value.append("high") }
        highOp.priority = .high

        // When
        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(order.value == ["high", "normal", "low"])
    }

    @Test func priorityCanBeUpdatedBeforeExecution() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true

        let order = Ref<[String]>([])

        let op1 = queue.add { order.value.append("first") }
        let op2 = queue.add { order.value.append("second") }

        // When – boost the second item's priority
        op1.priority = .low
        op2.priority = .high

        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(order.value == ["second", "first"])
    }

    @Test func fifoOrderWithinSamePriority() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        let order = Ref<[Int]>([])

        // When – all items have the same priority
        queue.add { order.value.append(1) }
        queue.add { order.value.append(2) }
        queue.add { order.value.append(3) }

        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()

        // Then – FIFO within the same priority bucket
        #expect(order.value == [1, 2, 3])
    }

    @Test func decreasingPriorityMovesOperationBackward() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        let order = Ref<[String]>([])

        let opA = queue.add { order.value.append("A") }
        opA.priority = .high

        let opB = queue.add { order.value.append("B") }
        opB.priority = .high

        queue.add { order.value.append("C") }

        // When – drop A from high to low
        opA.priority = .low

        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()

        // Then – B (high), C (normal), A (low)
        #expect(order.value == ["B", "C", "A"])
    }

    @Test func decreasedPriorityGoesAheadOfExistingLowerPriorityItems() async {
        // Given – A(high), B(normal), C(normal)
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        let order = Ref<[String]>([])

        let opA = queue.add { order.value.append("A") }
        opA.priority = .high

        queue.add { order.value.append("B") }
        queue.add { order.value.append("C") }

        // When – drop A from high to normal; it should go *ahead* of B and C
        opA.priority = .normal

        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()

        // Then – A was once higher priority, so it leads the normal bucket
        #expect(order.value == ["A", "B", "C"])
    }

    @Test func decreasedPriorityPrependsAcrossMultipleDrops() async {
        // Given – A(veryHigh), B(normal), C(normal)
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        let order = Ref<[String]>([])

        let opA = queue.add { order.value.append("A") }
        opA.priority = .veryHigh

        queue.add { order.value.append("B") }
        queue.add { order.value.append("C") }

        // When – drop A from veryHigh to normal
        opA.priority = .normal

        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()

        // Then – A prepended into normal bucket, ahead of B and C
        #expect(order.value == ["A", "B", "C"])
    }

    @Test func increasedPriorityAppendsAfterExistingHigherPriorityItems() async {
        // Given – A(normal), B(high), C(high)
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        let order = Ref<[String]>([])

        let opA = queue.add { order.value.append("A") }
        let opB = queue.add { order.value.append("B") }
        opB.priority = .high
        let opC = queue.add { order.value.append("C") }
        opC.priority = .high

        // When – boost A from normal to high; it should go *after* B and C (FIFO)
        opA.priority = .high

        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()

        // Then – B and C were already high, A appended behind them
        #expect(order.value == ["B", "C", "A"])
    }

    @Test func twoDecreasesPrependInOrder() async {
        // Given – A(high), B(high), C(normal)
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        let order = Ref<[String]>([])

        let opA = queue.add { order.value.append("A") }
        opA.priority = .high
        let opB = queue.add { order.value.append("B") }
        opB.priority = .high
        queue.add { order.value.append("C") }

        // When – drop both A then B to normal; each prepend goes to front
        opA.priority = .normal  // normal bucket: [A]
        opB.priority = .normal  // normal bucket: [B, A, C]

        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()

        // Then – B was prepended last so it's first, then A, then C
        #expect(order.value == ["B", "A", "C"])
    }

    @Test func multiplePriorityChangesBeforeExecution() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        let order = Ref<[String]>([])

        let opA = queue.add { order.value.append("A") }
        let opB = queue.add { order.value.append("B") }

        // When – move A through several priorities
        opA.priority = .high
        opA.priority = .veryHigh
        opA.priority = .low   // final

        opB.priority = .normal // stays normal

        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()

        // Then – B (normal) before A (low)
        #expect(order.value == ["B", "A"])
    }

    @Test func priorityChangeOfRunningOperationIsNoOp() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let started = TestExpectation()
        let gate = TestExpectation()

        let op = queue.add {
            started.fulfill()
            await gate.wait()
        }

        await started.wait()

        // When – operation is already running (node is nil)
        op.priority = .veryHigh // should not crash

        // Then
        #expect(op.priority == .veryHigh)

        // Cleanup
        gate.fulfill()
        await queue.waitUntilAllOperationsAreFinished()
    }

    // MARK: - Cancellation

    @Test func cancelledOperationIsNotExecuted() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        let executed = Ref(false)

        let operation = queue.add { executed.value = true }

        // When – cancel, then add a sentinel to prove the queue drained
        operation.cancel()
        let sentinel = Ref(false)
        queue.add { sentinel.value = true }
        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(!executed.value)
        #expect(sentinel.value)
    }

    @Test func cancellingOperationRemovesItFromPending() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true

        let done = Ref(false)
        let op1 = queue.add { done.value = true }
        let op2 = queue.add { }

        // When
        op2.cancel()
        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(done.value)
        #expect(!op1.isCancelled)
        #expect(op2.isCancelled)
    }

    @Test func cancellingAlreadyCancelledOperationIsNoop() {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let operation = queue.add { }

        // When
        operation.cancel()
        operation.cancel()

        // Then – no crash, still cancelled
        #expect(operation.isCancelled)
    }

    @Test func cancellingRunningOperationCancelsUnderlyingTask() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let started = TestExpectation()
        let taskWasCancelled = Ref(false)
        let gate = TestExpectation()

        let operation = queue.add {
            started.fulfill()
            await withTaskCancellationHandler {
                await gate.wait()
            } onCancel: {
                taskWasCancelled.value = true
                gate.fulfill() // unblock the closure so it can return
            }
        }

        await started.wait()

        // When
        operation.cancel()
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(taskWasCancelled.value)
    }

    @Test func cancelledItemIsSkippedDuringDrain() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true

        let order = Ref<[Int]>([])

        queue.add { order.value.append(1) }
        let op2 = queue.add { order.value.append(2) }
        queue.add { order.value.append(3) }

        // When – cancel the middle item
        op2.cancel()
        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(order.value == [1, 3])
    }

    // MARK: - Suspension

    @Test func suspendedQueueDoesNotExecuteWork() {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        let executed = Ref(false)

        // When – drain() exits immediately because isSuspended is true
        queue.add { executed.value = true }

        // Then
        #expect(!executed.value)
    }

    @Test func resumingQueueExecutesPendingWork() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        let executed = Ref(false)

        queue.add { executed.value = true }

        // When
        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(executed.value)
    }

    @Test func suspendingAlreadySuspendedQueueIsNoop() {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)

        // When
        queue.isSuspended = true
        queue.isSuspended = true

        // Then – no crash
        #expect(queue.isSuspended)
    }

    @Test func resumingAlreadyResumedQueueIsNoop() {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)

        // When
        queue.isSuspended = false

        // Then – no crash
        #expect(!queue.isSuspended)
    }

    // MARK: - Throwing Work

    @Test func throwingWorkFreesSlot() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let secondRan = Ref(false)

        struct TestError: Error {}

        // When – first work throws, second should still run
        queue.add { throw TestError() }
        queue.add { secondRan.value = true }
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(secondRan.value)
    }

    // MARK: - TaskQueue.Operation

    @Test func defaultPriorityIsNormal() {
        let operation = TaskQueue.Operation()
        #expect(operation.priority == .normal)
    }

    @Test func priorityChangeFiresEvent() {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        var didChange = false
        queue.onEvent = { event in
            if case .priorityChanged = event { didChange = true }
        }
        let operation = queue.add { }

        // When
        operation.priority = .high

        // Then
        #expect(didChange)
        #expect(operation.priority == .high)
    }

    @Test func settingSamePriorityDoesNotFireEvent() {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        var changeCount = 0
        queue.onEvent = { event in
            if case .priorityChanged = event { changeCount += 1 }
        }
        let operation = queue.add { }

        // When
        operation.priority = .normal

        // Then
        #expect(changeCount == 0)
    }

    @Test func cancelSetsFlag() {
        let operation = TaskQueue.Operation()
        operation.cancel()
        #expect(operation.isCancelled)
    }

    @Test func cancelFiresEvent() {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        var called = false
        queue.onEvent = { event in
            if case .cancelled = event { called = true }
        }
        let operation = queue.add { }

        // When
        operation.cancel()

        // Then
        #expect(called)
    }

    // MARK: - onEvent(.enqueued)

    @Test func onEventEnqueuedCalledForEachAdd() {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 2)
        var enqueuedCount = 0
        queue.onEvent = { event in
            if case .enqueued = event { enqueuedCount += 1 }
        }

        // When
        queue.add { }
        queue.add { }
        queue.add { }

        // Then
        #expect(enqueuedCount == 3)
    }

    @Test func onEventEnqueuedReceivesCorrectOperation() {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true

        var enqueuedOperations = [TaskQueue.Operation]()
        queue.onEvent = { event in
            if case .enqueued(let op) = event { enqueuedOperations.append(op) }
        }

        // When
        let op1 = queue.add { }
        let op2 = queue.add { }

        // Then
        #expect(enqueuedOperations.count == 2)
        #expect(enqueuedOperations[0] === op1)
        #expect(enqueuedOperations[1] === op2)
    }

    // MARK: - operationCount

    @Test func operationCountReflectsPendingItems() {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true

        // When
        queue.add { }
        queue.add { }

        // Then – 2 pending, 0 running
        #expect(queue.operationCount == 2)
    }

    @Test func operationCountIncludesRunningItems() {
        // Given – unsuspended queue, items start immediately
        let queue = TaskQueue(maxConcurrentTaskCount: 1)

        // When
        queue.add { }
        queue.add { }

        // Then – 1 running (started by drain) + 1 pending
        #expect(queue.operationCount == 2)
    }

    @Test func operationCountIsZeroWhenEmpty() {
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        #expect(queue.operationCount == 0)
    }

    @Test func operationCountDecreasesAfterCancellation() {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        let op = queue.add { }
        #expect(queue.operationCount == 1)

        // When
        op.cancel()

        // Then
        #expect(queue.operationCount == 0)
    }

    // MARK: - waitForOperations helper

    @Test func waitForOperationsHelper() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true

        // When
        let operations = await queue.waitForOperations(count: 2) {
            queue.add { }
            queue.add { }
        }

        // Then
        #expect(operations.count == 2)
    }

    // MARK: - Suspension (Running + Pending)

    @Test func suspendingQueueDoesNotAffectRunningOperations() async {
        // Given – one running, one pending
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let item1Started = TestExpectation()
        let item1Finished = TestExpectation()
        let gate = TestExpectation()
        let item2Ran = Ref(false)

        queue.add {
            item1Started.fulfill()
            await gate.wait()
            item1Finished.fulfill()
        }
        queue.add { item2Ran.value = true }

        await item1Started.wait()

        // When – suspend while item 1 is running
        queue.isSuspended = true
        gate.fulfill()

        // Then – item 1 completes despite suspension
        await item1Finished.wait()

        // Item 2 did NOT start because the queue was suspended
        #expect(!item2Ran.value)
        #expect(queue.pendingCount == 1)

        // Resume and let item 2 run
        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()
        #expect(item2Ran.value)
    }

    // MARK: - onEvent(.finished)

    @Test func onEventFinishedCalledForEachCompletion() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        var finishedCount = 0
        queue.onEvent = { event in
            if case .finished = event { finishedCount += 1 }
        }

        // When
        queue.add { }
        queue.add { }
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(finishedCount == 2)
    }

    // MARK: - Edge Cases

    @Test func emptyQueueDoesNotCrash() {
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        #expect(!queue.isSuspended)
        #expect(queue.operationCount == 0)
    }

    @Test func waitUntilAllOperationsAreFinishedOnEmptyQueue() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)

        // When/Then – returns immediately, no hang
        await queue.waitUntilAllOperationsAreFinished()
    }

    @Test func addingWorkAfterQueueHasDrained() async {
        // Given – queue has already processed work
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.add { }
        await queue.waitUntilAllOperationsAreFinished()
        #expect(queue.operationCount == 0)

        // When – add more work
        let ran = Ref(false)
        queue.add { ran.value = true }
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(ran.value)
    }

    @Test func priorityChangeOnCancelledOperationIsNoOp() {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        var priorityEventCount = 0
        queue.onEvent = { event in
            if case .priorityChanged = event { priorityEventCount += 1 }
        }
        let op = queue.add { }
        op.cancel()

        // When – change priority after cancellation (node is nil)
        op.priority = .high

        // Then – priority value updates but no queue event fires
        #expect(op.priority == .high)
        #expect(priorityEventCount == 0)
    }

    @Test func cancellingRunningOperationDoesNotChangePendingCount() async {
        // Given – one running, one pending
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let started = TestExpectation()
        let gate = TestExpectation()

        let runningOp = queue.add {
            started.fulfill()
            await gate.wait()
        }
        queue.add { }
        await started.wait()

        // Snapshot: 1 running + 1 pending = 2
        #expect(queue.operationCount == 2)

        // When – cancel the running operation
        runningOp.cancel()

        // Then – pendingCount unchanged (still 1 pending), running slot freed on completion
        #expect(queue.pendingCount == 1)

        gate.fulfill()
        await queue.waitUntilAllOperationsAreFinished()
    }
}
