// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

@testable import Nuke
import Testing
import Foundation
import os

// Stress tests for the pipeline's public surface used from many threads at
// once. Unlike `ThreadSafetyTests`, which only has to survive the traffic,
// each test here checks an outcome that a lost update, a stale hop, or a
// leaked task would get wrong.

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineContentionTests {
    /// `taskId` "uniquely identifies the task within a given pipeline", which
    /// has to hold for the tasks created on different threads at once.
    @Test func taskIdentifiersAreUniqueAcrossThreads() async {
        // Given
        let dataLoader = MockDataLoader()
        dataLoader.isSuspended = true
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        // When
        let tasks = makeTasks(threads: 16, perThread: 100) { _, _ in
            pipeline.imageTask(with: Test.request)
        }

        // Then
        #expect(Set(tasks.map(\.taskId)).count == 1600)
        #expect(Set(tasks.map(\.id)).count == 1600)

        // Cleanup
        tasks.forEach { $0.cancel() }
        _ = await outcomes(of: tasks)
    }

    /// Tasks for the same image, created on many threads while the download
    /// is pending, all join the one download and get the same image.
    @Test func coalescedTasksFromManyThreadsShareOneDownload() async {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        // When all tasks start before the data loader is allowed to respond
        let tasks = await withSuspendedDataLoading(for: pipeline, expectedCount: 64) {
            makeTasks(threads: 8, perThread: 8) { _, _ in
                pipeline.imageTask(with: Test.request)
            }
        }
        let results = await outcomes(of: tasks)

        // Then
        #expect(dataLoader.createdTaskCount == 1)
        let images = results.compactMap { try? $0?.get().image }
        #expect(images.count == 64)
        #expect(images.allSatisfy { $0 === images.first })
    }

    /// Cancelling some of the coalesced tasks – each from several threads at
    /// once – finishes each of them exactly once and never cancels the
    /// download the others still wait for.
    @Test func cancellingSomeCoalescedTasksKeepsTheSharedDownload() async {
        // Given
        let dataLoader = MockDataLoader()
        dataLoader.isSuspended = true
        let delegate = FinishedEventCounter()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let cancellations = NotificationCounter(MockDataLoader.DidCancelTask, object: dataLoader)
        let downloadStarted = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let tasks = makeTasks(threads: 8, perThread: 8) { _, _ in
            pipeline.imageTask(with: Test.request)
        }
        await downloadStarted.wait()

        // When every other task is cancelled from four threads at once
        let cancelled = stride(from: 1, to: tasks.count, by: 2).map { tasks[$0] }
        DispatchQueue.concurrentPerform(iterations: cancelled.count * 4) { index in
            cancelled[index / 4].cancel()
        }
        dataLoader.isSuspended = false
        let results = await outcomes(of: tasks)

        // Then
        for (index, result) in results.enumerated() {
            if index % 2 == 0 {
                #expect(result?.isSuccess == true)
            } else {
                // A cancellation that lands after the task finished is a no-op.
                #expect(result?.isSuccess == true || result?.error == .cancelled)
                #expect(tasks[index].isCancelled)
            }
        }
        await drainPipeline()
        #expect(delegate.finishedCount(for: tasks) == Array(repeating: 1, count: tasks.count))
        #expect(cancellations.count == 0)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(await pipeline.taskCount == 0)
    }

    /// Cancelling every coalesced task, from many threads at once, cancels the
    /// shared download once and finishes every task with `.cancelled`.
    @Test func cancellingEveryCoalescedTaskCancelsTheDownloadOnce() async {
        // Given
        let dataLoader = MockDataLoader()
        dataLoader.isSuspended = true
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let cancellations = NotificationCounter(MockDataLoader.DidCancelTask, object: dataLoader)
        let downloadStarted = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let tasks = makeTasks(threads: 8, perThread: 8) { _, _ in
            pipeline.imageTask(with: Test.request)
        }
        await downloadStarted.wait()

        // When
        await notification(MockDataLoader.DidCancelTask, object: dataLoader) {
            DispatchQueue.concurrentPerform(iterations: tasks.count * 2) { index in
                tasks[index / 2].cancel()
            }
        }
        let results = await outcomes(of: tasks)

        // Then
        #expect(results.allSatisfy { $0?.error == .cancelled })
        #expect(cancellations.count == 1)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(await pipeline.taskCount == 0)
    }

    /// `invalidate()` racing the creation of tasks on other threads: every
    /// task fails – the outstanding ones with `.cancelled`, the ones that
    /// start after it with `.pipelineInvalidated` – every download the tasks
    /// started is cancelled, and nothing is left behind.
    @Test func invalidatingWhileTasksAreCreatedFailsThemAll() async {
        // Given
        let dataLoader = MockDataLoader()
        dataLoader.isSuspended = true // Nothing can succeed
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isRateLimiterEnabled = false
        }
        let cancellations = NotificationCounter(MockDataLoader.DidCancelTask, object: dataLoader)

        // When
        let tasks = makeTasks(threads: 8, perThread: 60) { thread, index in
            if thread == 0 && index == 30 {
                pipeline.invalidate()
            }
            return pipeline.imageTask(with: URL(string: "https://example.com/\(index % 20).jpeg")!)
        }
        let results = await outcomes(of: tasks)

        // Then
        for result in results {
            #expect(result?.error == .cancelled || result?.error == .pipelineInvalidated)
        }
        #expect(await pipeline.taskCount == 0)
        #expect(cancellations.count == dataLoader.createdTaskCount)

        let lateResult = await outcomes(of: [pipeline.imageTask(with: Test.request)]).first
        #expect(lateResult??.error == .pipelineInvalidated)
    }

    /// A task created after `invalidate()` returned fails, whatever the QoS
    /// of the thread that invalidated the pipeline: the invalidation and the
    /// start of the task reach the actor in no particular order, so the task
    /// can't rely on the actor knowing about the invalidation.
    @Test(arguments: [DispatchQoS.QoSClass.background, .userInitiated])
    func requestCreatedAfterInvalidateReturnedFails(invalidateQoS: DispatchQoS.QoSClass) async {
        // Given an image in the memory cache, so that nothing but the
        // invalidation can fail the task
        let imageCache = ImageCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = imageCache
        }
        imageCache[ImageCacheKey(request: Test.request)] = Test.container

        // When `invalidate()` returns, and only then a new task is created,
        // with the actor busy so that both reach it at once
        let gate = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        Task.detached { @ImagePipelineActor in
            entered.signal()
            blockOnSemaphore(gate)
        }
        blockOnSemaphore(entered)
        run(on: invalidateQoS) { pipeline.invalidate() }
        let task = run(on: .userInitiated) { pipeline.imageTask(with: Test.request) }
        gate.signal()

        // Then
        let result = await outcomes(of: [task]).first
        #expect(result??.error == .pipelineInvalidated)
    }

    /// A storm of loads, cancellations, and priority changes from many
    /// threads. A task only fails if it was cancelled, the pipeline releases
    /// every task, and no finished work stays behind to be joined: loading the
    /// same images again goes back to the data loader and succeeds.
    @Test func stormLeavesNoTasksOrStaleWorkBehind() async throws {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isRateLimiterEnabled = false
        }
        let urls = (0..<20).map { URL(string: "https://example.com/\($0).jpeg")! }
        let resize = ImageProcessors.Resize(size: CGSize(width: 40, height: 40), unit: .pixels)

        // When
        let tasks = makeTasks(threads: 8, perThread: 120) { _, index in
            var request = ImageRequest(url: urls[index % urls.count])
            if index % 3 == 0 {
                request.processors = [resize]
            }
            let task = pipeline.imageTask(with: request)
            switch Int.random(in: 0..<6) {
            case 0: task.cancel()
            case 1: DispatchQueue.global().async { task.cancel() }
            case 2: task.priority = .veryHigh
            case 3: DispatchQueue.global().async { task.priority = .veryLow }
            default: break
            }
            return task
        }
        let results = await outcomes(of: tasks)

        // Then
        for (task, result) in zip(tasks, results) {
            let status = task.status
            #expect(status.result != nil)
            if let error = result?.error {
                #expect(error == .cancelled)
                #expect(status.isCancelled)
            }
        }
        #expect(await pipeline.taskCount == 0)

        let createdTaskCount = dataLoader.createdTaskCount
        for url in urls {
            _ = try await pipeline.image(for: url)
        }
        #expect(dataLoader.createdTaskCount == createdTaskCount + urls.count)
    }

    /// "The user does not need to hold a strong reference to the pipeline":
    /// pipelines created on many threads and dropped right after starting a
    /// task finish their tasks, and are released once the tasks are done.
    @Test func droppedPipelinesFinishTheirTasksAndAreReleased() async {
        // Given
        let dataLoader = MockDataLoader()
        let pipelines = OSAllocatedUnfairLock(initialState: [WeakRef<ImagePipeline>]())

        // When
        let tasks = makeTasks(threads: 8, perThread: 5) { thread, index in
            let pipeline = ImagePipeline {
                $0.dataLoader = dataLoader
                $0.imageCache = nil
            }
            pipelines.withLock { $0.append(WeakRef(pipeline)) }
            var request = ImageRequest(url: URL(string: "https://example.com/\(thread)-\(index).jpeg")!)
            if index % 2 == 0 {
                request.processors = [ImageProcessors.Resize(width: 20, unit: .pixels)]
            }
            return pipeline.imageTask(with: request)
        }
        let results = await outcomes(of: tasks)

        // Then
        #expect(results.allSatisfy { $0?.isSuccess == true })
        await waitUntil(timeout: .seconds(60)) {
            pipelines.withLock { $0.allSatisfy { $0.value == nil } }
        }
    }

    /// Streams subscribed from many threads at arbitrary points in the task
    /// lifetime – before, during, and after it finishes, with some tasks
    /// cancelled – each deliver a single terminal event, last, matching the
    /// result the task recorded, with the progress never going backwards.
    @Test func everyEventStreamEndsWithOneMatchingFinishedEvent() async {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isRateLimiterEnabled = false
        }
        let tasks = (0..<40).map { index in
            pipeline.imageTask(with: URL(string: "https://example.com/\(index % 10).jpeg")!)
        }

        // When
        let streams = OSAllocatedUnfairLock(initialState: [(Int, AsyncStream<ImageTask.Event>)]())
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for (index, task) in tasks.enumerated() where index % 8 == worker {
                let early = task.events
                if index % 5 == 0 {
                    task.cancel()
                }
                let late = task.events
                streams.withLock { $0 += [(index, early), (index, late)] }
            }
        }
        _ = await outcomes(of: tasks)
        let finishedStreams = tasks.enumerated().map { ($0.offset, $0.element.events) }
        let allStreams = streams.withLock { $0 } + finishedStreams

        // Then
        let failures = await withTaskGroup(of: [String].self) { group in
            for (index, stream) in allStreams {
                group.addTask {
                    var events: [ImageTask.Event] = []
                    for await event in stream {
                        events.append(event)
                    }
                    return validate(events, of: tasks[index], index: index)
                }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }
        #expect(failures == [])
    }

    /// "It is safe to await the response more than once ... every caller gets
    /// the same outcome" – including when one of the awaiting Swift tasks is
    /// cancelled, which cancels the image task for all of them.
    @Test func concurrentAwaitersGetTheSameOutcome() async {
        // Given
        let dataLoader = MockDataLoader()
        dataLoader.isSuspended = true
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let cancelledTask = pipeline.imageTask(with: URL(string: "https://example.com/cancelled.jpeg")!)
        let loadedTask = pipeline.imageTask(with: URL(string: "https://example.com/loaded.jpeg")!)

        // When eight Swift tasks await each image task, and one of the
        // awaiters of the first one is cancelled
        let cancelledAwaiters = (0..<8).map { _ in makeAwaiter(of: cancelledTask) }
        let loadedAwaiters = (0..<8).map { _ in makeAwaiter(of: loadedTask) }
        cancelledAwaiters[3].cancel()
        let cancelledResults = await results(of: cancelledAwaiters)
        dataLoader.isSuspended = false
        let loadedResults = await results(of: loadedAwaiters)

        // Then
        #expect(cancelledResults.allSatisfy { $0.error == .cancelled })
        #expect(cancelledTask.isCancelled)
        let images = loadedResults.compactMap { try? $0.get().image }
        #expect(images.count == 8)
        #expect(images.allSatisfy { $0 === images.first })
    }
}

// MARK: - Diagnostics

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDiagnosticsContentionTests {
    /// The runtime switch is flipped from another thread while tasks start,
    /// coalesce, and get cancelled. "A task is either recorded in full or not
    /// at all": every record that exists belongs to its task, agrees with the
    /// result, and describes a well-formed chain of jobs the task reached.
    @Test func recordsStayConsistentWhileTheSwitchIsFlipped() async {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isRateLimiterEnabled = false
            $0.isDiagnosticsEnabled = true
        }
        let isDone = OSAllocatedUnfairLock(initialState: false)
        let toggler = Task.detached {
            // Keep flipping until every task has finished.
            while !isDone.withLock({ $0 }) {
                pipeline.diagnostics.isEnabled.toggle()
                await Task.yield()
            }
        }

        // When
        let tasks = makeTasks(threads: 8, perThread: 50) { _, index in
            let task = pipeline.imageTask(with: URL(string: "https://example.com/\(index % 10).jpeg")!)
            if index % 4 == 0 {
                task.cancel()
            }
            return task
        }
        let results = await outcomes(of: tasks)
        isDone.withLock { $0 = true }
        await toggler.value

        // Then
        for (task, result) in zip(tasks, results) {
            guard let metrics = task.metrics else { continue }
            #expect(metrics.taskID == task.taskId)
            #expect(metrics.pipelineID == pipeline.id)
            #expect(metrics.endedAt >= metrics.createdAt)
            switch result {
            case .success?: #expect(metrics.outcome == .success)
            case .failure(.cancelled)?: #expect(metrics.outcome == .cancelled)
            default: Issue.record("Unexpected result: \(String(describing: result))")
            }
            #expect(metrics.rootJobID == metrics.jobs.first?.id)
            #expect(metrics.isCoalesced == metrics.jobs.contains { $0.joinedAt != nil })
            for (job, parent) in zip(metrics.jobs, metrics.jobs.dropFirst()) {
                #expect(job.parentID == parent.id)
            }
            #expect(metrics.jobs.last?.parentID == nil)
            for job in metrics.jobs {
                #expect(job.taskIDs.contains(task.taskId), "The task reached every job in its chain")
            }
        }

        // The switch is read once per task, when it starts.
        pipeline.diagnostics.isEnabled = true
        let task = pipeline.imageTask(with: Test.request)
        _ = await outcomes(of: [task])
        #expect(task.metrics?.outcome == .success)
    }
}

// MARK: - Helpers

/// Runs the closure on a global queue with the given QoS and waits for it.
private func run<T: Sendable>(on qos: DispatchQoS.QoSClass, _ work: @Sendable @escaping () -> T) -> T {
    let result = OSAllocatedUnfairLock<T?>(initialState: nil)
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: qos).async {
        let value = work()
        result.withLock { $0 = value }
        done.signal()
    }
    done.wait()
    return result.withLock { $0! }
}

/// Blocks the calling thread, from an async context.
private func blockOnSemaphore(_ semaphore: DispatchSemaphore) {
    semaphore.wait()
}

/// Creates `threads * perThread` tasks, `perThread` on each of `threads`
/// threads running at once, and returns them in a stable order.
private func makeTasks(threads: Int, perThread: Int, _ make: @Sendable (_ thread: Int, _ index: Int) -> ImageTask) -> [ImageTask] {
    let tasks = OSAllocatedUnfairLock(initialState: [[ImageTask]](repeating: [], count: threads))
    DispatchQueue.concurrentPerform(iterations: threads) { thread in
        let created = (0..<perThread).map { make(thread, $0) }
        tasks.withLock { $0[thread] = created }
    }
    return tasks.withLock { $0.flatMap { $0 } }
}

/// Awaits the responses of the given tasks. A task that never finishes is
/// reported as an issue (and its outcome as `nil`) instead of hanging the run.
private func outcomes(of tasks: [ImageTask], timeout: Duration = .seconds(120)) async -> [Result<ImageResponse, ImagePipeline.Error>?] {
    let collected = OSAllocatedUnfairLock(initialState: [Result<ImageResponse, ImagePipeline.Error>?](repeating: nil, count: tasks.count))
    let expectation = TestExpectation()
    Task {
        await withTaskGroup(of: Void.self) { group in
            for (index, task) in tasks.enumerated() {
                group.addTask {
                    let result = await task.outcome
                    collected.withLock { $0[index] = result }
                }
            }
        }
        expectation.fulfill()
    }
    await expectation.wait(timeout: timeout)
    return collected.withLock { $0 }
}

private func makeAwaiter(of task: ImageTask) -> Task<Result<ImageResponse, ImagePipeline.Error>, Never> {
    Task.detached {
        await task.outcome
    }
}

private func results(of awaiters: [Task<Result<ImageResponse, ImagePipeline.Error>, Never>]) async -> [Result<ImageResponse, ImagePipeline.Error>] {
    var results: [Result<ImageResponse, ImagePipeline.Error>] = []
    for awaiter in awaiters {
        results.append(await awaiter.value)
    }
    return results
}

/// Checks one stream of events against the task it belongs to.
private func validate(_ events: [ImageTask.Event], of task: ImageTask, index: Int) -> [String] {
    var failures: [String] = []
    var finishedCount = 0
    var lastProgress: Int64 = -1
    for event in events {
        switch event {
        case .finished:
            finishedCount += 1
        case .progress(let progress):
            if progress.completed < lastProgress {
                failures.append("task \(index): progress went back from \(lastProgress) to \(progress.completed)")
            }
            lastProgress = progress.completed
        case .preview:
            break
        }
    }
    if finishedCount != 1 {
        failures.append("task \(index): \(finishedCount) finished events")
    }
    guard case .finished(let result)? = events.last else {
        failures.append("task \(index): the stream didn't end with the finished event")
        return failures
    }
    switch (result, task.status.result) {
    case (.success(let lhs), .success(let rhs)?) where lhs.image === rhs.image:
        break
    case (.failure(let lhs), .failure(let rhs)?) where lhs == rhs:
        break
    default:
        failures.append("task \(index): the stream says \(result), the status says \(String(describing: task.status.result))")
    }
    return failures
}

/// Counts the `.finished` events the delegate receives for each task.
private final class FinishedEventCounter: ImagePipeline.Delegate, @unchecked Sendable {
    private let counts = OSAllocatedUnfairLock(initialState: [ObjectIdentifier: Int]())

    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        if case .finished = event {
            counts.withLock { $0[ObjectIdentifier(task), default: 0] += 1 }
        }
    }

    func finishedCount(for tasks: [ImageTask]) -> [Int] {
        counts.withLock { counts in tasks.map { counts[ObjectIdentifier($0)] ?? 0 } }
    }
}

/// Counts the notifications posted with the given name by the given object.
private final class NotificationCounter: @unchecked Sendable {
    private let _count = OSAllocatedUnfairLock(initialState: 0)
    private var token: NSObjectProtocol?

    var count: Int { _count.withLock { $0 } }

    init(_ name: Notification.Name, object: AnyObject) {
        token = NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [_count] _ in
            _count.withLock { $0 += 1 }
        }
    }

    deinit {
        token.map(NotificationCenter.default.removeObserver)
    }
}

private extension ImageTask {
    /// The response, or the error the task failed with.
    var outcome: Result<ImageResponse, ImagePipeline.Error> {
        get async {
            do {
                return .success(try await response)
            } catch {
                return .failure(error)
            }
        }
    }
}
