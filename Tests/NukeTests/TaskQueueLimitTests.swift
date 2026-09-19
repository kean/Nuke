// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5))) @ImagePipelineActor
struct TaskQueueLimitTests {
    // MARK: - Limit

    @Test func defaultLimitMatchesTheNumberOfCores() {
        #expect(TaskQueue().maxConcurrentTaskCount == ProcessInfo.processInfo.processorCount)
    }

    @Test func zeroLimitRunsNothingUntilItIsRaised() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 0)
        let didRun = TestExpectation()

        // When
        queue.add { didRun.fulfill() }

        // Then
        #expect(queue.runningCount == 0)
        #expect(queue.pendingCount == 1)

        queue.maxConcurrentTaskCount = 1
        await didRun.wait()
    }

    @Test func raisingTheLimitStartsTheHighestPriorityWorkFirst() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 0)
        let started = Ref<[String]>([])
        let didStartTwo = TestExpectation()
        let gate = AsyncGate()
        func add(_ name: String, priority: TaskPriority) {
            let operation = queue.add {
                started.value.append(name)
                if started.value.count == 2 {
                    didStartTwo.fulfill()
                }
                await gate.wait()
            }
            operation.priority = priority
        }
        add("low", priority: .low)
        add("high", priority: .high)
        add("normal", priority: .normal)

        // When
        queue.maxConcurrentTaskCount = 2
        await didStartTwo.wait()

        // Then
        #expect(Set(started.value) == ["high", "normal"])
        #expect(queue.runningCount == 2)
        #expect(queue.pendingCount == 1)

        gate.open()
        await queue.waitUntilAllOperationsAreFinished()
        #expect(started.value.last == "low")
    }

    @Test func raisingTheLimitOfASuspendedQueueStartsNothing() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 0)
        queue.isSuspended = true
        let didRun = Ref(false)
        queue.add { didRun.value = true }

        // When
        queue.maxConcurrentTaskCount = 1
        await Task { @ImagePipelineActor in }.value

        // Then
        #expect(!didRun.value)
        #expect(queue.pendingCount == 1)

        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()
        #expect(didRun.value)
    }

    // MARK: - Suspension

    /// Resuming schedules the drain for later, and the queue has to check
    /// whether it's still resumed when the drain runs.
    @Test func suspendingRightAfterResumingStartsNothing() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        queue.isSuspended = true
        let didRun = Ref(false)
        queue.add { didRun.value = true }

        // When
        queue.isSuspended = false
        queue.isSuspended = true
        await Task { @ImagePipelineActor in }.value

        // Then
        #expect(!didRun.value)
        #expect(queue.pendingCount == 1)

        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()
        #expect(didRun.value)
    }

    // MARK: - Re-entrancy

    @Test func workAddedByRunningWorkRunsWhenTheSlotIsFree() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let events = Ref<[String]>([])

        // When
        queue.add {
            events.value.append("outer started")
            queue.add { events.value.append("inner") }
            // The outer work never suspends, so the order of the events alone
            // can't tell whether the inner work took a second slot.
            #expect(queue.runningCount == 1)
            #expect(queue.pendingCount == 1)
            events.value.append("outer finished")
        }
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(events.value == ["outer started", "outer finished", "inner"])
    }

    @Test func workCancellingItsOwnOperationFreesTheSlotWhenItReturns() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let operation = Ref<TaskQueue.Operation?>(nil)
        let wasCancelled = Ref(false)
        let nextDidRun = Ref(false)

        // When
        operation.value = queue.add {
            operation.value?.cancel()
            wasCancelled.value = Task.isCancelled
        }
        queue.add { nextDidRun.value = true }
        await queue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(wasCancelled.value)
        #expect(operation.value?.isCancelled == true)
        #expect(nextDidRun.value)
        #expect(queue.runningCount == 0)
        #expect(queue.pendingCount == 0)
    }

    @Test func cancellingAFinishedOperationChangesNothing() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let operation = queue.add {}
        await queue.waitUntilAllOperationsAreFinished()

        // When
        operation.cancel()
        operation.priority = .veryHigh

        // Then
        #expect(operation.isCancelled)
        #expect(queue.runningCount == 0)
        #expect(queue.pendingCount == 0)

        let didRun = TestExpectation()
        queue.add { didRun.fulfill() }
        await didRun.wait()
    }

    // MARK: - Lifetime

    @Test func operationsDoNotRetainTheirQueue() {
        // Given
        var queue: TaskQueue? = TaskQueue(maxConcurrentTaskCount: 1)
        queue?.isSuspended = true
        let didRun = Ref(false)
        let operation = queue?.add { didRun.value = true }
        weak var weakQueue: TaskQueue?
        weakQueue = queue

        // When
        queue = nil

        // Then the pending work is gone with the queue, and the handle is
        // still safe to use
        #expect(weakQueue == nil)
        operation?.priority = .high
        operation?.cancel()
        #expect(operation?.isCancelled == true)
        #expect(!didRun.value)
    }

    @Test func runningWorkFinishesAfterTheQueueIsGone() async {
        // Given
        var queue: TaskQueue? = TaskQueue(maxConcurrentTaskCount: 1)
        let didStart = TestExpectation()
        let didFinish = TestExpectation()
        let gate = AsyncGate()
        queue?.add {
            didStart.fulfill()
            await gate.wait()
            didFinish.fulfill()
        }
        await didStart.wait()
        weak var weakQueue: TaskQueue?
        weakQueue = queue

        // When
        queue = nil
        gate.open()

        // Then
        #expect(weakQueue == nil)
        await didFinish.wait()
    }
}
