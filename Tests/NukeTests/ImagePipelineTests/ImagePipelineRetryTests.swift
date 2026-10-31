// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// Retries end-to-end. What a policy decides is in ``RetryPolicyTests``; this
/// is about what the pipeline does with the decision.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineRetryTests {
    private typealias Policy = ImagePipeline.RetryPolicy

    private let dataLoader = MockScriptedDataLoader()
    private let timedOut = MockScriptedDataLoader.Step.fail(URLError(.timedOut))

    private func makePipeline(policy: Policy? = .immediate(), delegate: (any ImagePipeline.Delegate)? = nil, _ configure: (inout ImagePipeline.Configuration) -> Void = { _ in }) -> ImagePipeline {
        ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.retryPolicy = policy
            configure(&$0)
        }
    }

    private func request(_ policy: Policy?, url: URL = Test.url) -> ImageRequest {
        var request = ImageRequest(url: url)
        request.retryPolicy = policy
        return request
    }

    /// Waits for an attempt to fail and for the wait before the retry to start.
    private func waitForRetry(of task: ImageTask) async {
        await Task { @ImagePipelineActor in
            await waitUntil { task._isWaitingForRetry }
        }.value
    }

    // MARK: - Retrying

    @Test func failedLoadIsRetried() async throws {
        dataLoader.steps = [timedOut]
        let task = makePipeline().imageTask(with: Test.request)

        let response = try await task.response

        #expect(response.image.sizeInPixels != .zero)
        #expect(dataLoader.requestCount == 2)
        #expect(task.status.retryCount == 1)
    }

    @Test func retriesUntilTheLoadSucceeds() async throws {
        dataLoader.steps = [timedOut, timedOut]
        let task = makePipeline(policy: .immediate(2)).imageTask(with: Test.request)

        _ = try await task.response

        #expect(dataLoader.requestCount == 3)
        #expect(task.status.retryCount == 2)
    }

    @Test func failsWithTheErrorOfTheLastAttempt() async throws {
        dataLoader.steps = [timedOut, .fail(URLError(.cannotFindHost)), .fail(URLError(.cannotConnectToHost)), .fail(URLError(.badServerResponse))]
        let task = makePipeline(policy: .immediate(2)).imageTask(with: Test.request)

        let result = await task._task.value

        guard case .failure(.dataLoadingFailed(let error as URLError)) = result else {
            Issue.record("Unexpected result: \(result)")
            return
        }
        #expect(error.code == .cannotConnectToHost)
        #expect(dataLoader.requestCount == 3)
    }

    @Test func noRetriesByDefault() async throws {
        dataLoader.steps = [timedOut]
        let task = makePipeline(policy: nil).imageTask(with: Test.request)

        #expect(await task._task.value.isFailure)

        #expect(dataLoader.requestCount == 1)
        #expect(task.status.retryCount == 0)
        #expect(ImagePipeline.Configuration().retryPolicy == nil)
    }

    @Test func permanentFailureIsNotRetried() async throws {
        dataLoader.steps = [.fail(DataLoader.Error.statusCodeUnacceptable(404))]
        let task = makePipeline().imageTask(with: Test.request)

        #expect(await task._task.value.isFailure)

        #expect(dataLoader.requestCount == 1)
    }

    @Test func failureToDecodeIsNotRetried() async throws {
        dataLoader.steps = [.serve(Data("not an image".utf8))]
        let task = makePipeline().imageTask(with: Test.request)

        guard case .failure(.decodingFailed) = await task._task.value else {
            Issue.record("Expected a decoding failure")
            return
        }
        #expect(dataLoader.requestCount == 1)
    }

    @Test func dataTaskIsRetried() async throws {
        dataLoader.steps = [timedOut]

        let (data, _) = try await makePipeline().data(for: Test.request)

        #expect(data == Test.data)
        #expect(dataLoader.requestCount == 2)
    }

    @Test func requestThatSkipsTheQueueIsRetried() async throws {
        dataLoader.steps = [timedOut]
        let request = ImageRequest(url: Test.url, options: [.skipDataLoadingQueue])

        _ = try await makePipeline().image(for: request)

        #expect(dataLoader.requestCount == 2)
    }

    @Test func dataClosureIsRetried() async throws {
        let attempts = EventCounter()
        let request = ImageRequest(id: "a", data: {
            attempts.increment()
            if attempts.count == 1 { throw URLError(.timedOut) }
            return Test.data
        })

        _ = try await makePipeline().image(for: request)

        #expect(attempts.count == 2)
    }

    @Test func dataClosureThatSkipsTheQueueIsRetried() async throws {
        let attempts = EventCounter()
        let request = ImageRequest(id: "a", data: {
            attempts.increment()
            if attempts.count == 1 { throw URLError(.timedOut) }
            return Test.data
        }, options: [.skipDataLoadingQueue])

        _ = try await makePipeline().image(for: request)

        #expect(attempts.count == 2)
    }

    @Test func imageClosureIsRetried() async throws {
        let attempts = EventCounter()
        let request = ImageRequest(id: "a", image: {
            attempts.increment()
            if attempts.count == 1 { throw URLError(.timedOut) }
            return ImageContainer(image: Test.image)
        })

        _ = try await makePipeline().image(for: request)

        #expect(attempts.count == 2)
    }

    @Test func closureThatReturnsNoDataIsAskedAboutButNotRetriedByThePolicy() async throws {
        let attempts = EventCounter()
        let delegate = MockRetryDelegate { $0.policy?.decision(for: $0) ?? .stop }
        let request = ImageRequest(id: "a", data: {
            attempts.increment()
            return Data()
        })

        await #expect(throws: ImagePipeline.Error.self) {
            _ = try await makePipeline(delegate: delegate).image(for: request)
        }

        #expect(attempts.count == 1)
        #expect(delegate.contexts.count == 1)
    }

    @Test func localResourceIsNotRetried() async throws {
        let delegate = MockRetryDelegate { _ in .retry(after: 0) }
        let url = URL(fileURLWithPath: "/nonexistent/image.jpeg")

        await #expect(throws: ImagePipeline.Error.self) {
            _ = try await makePipeline(delegate: delegate).image(for: url)
        }

        #expect(delegate.contexts.isEmpty)
    }

    // MARK: - Request Policy

    @Test func requestPolicyWorksWithoutAPipelinePolicy() async throws {
        dataLoader.steps = [timedOut]

        _ = try await makePipeline(policy: nil).image(for: request(.immediate()))

        #expect(dataLoader.requestCount == 2)
    }

    @Test func requestPolicyReplacesThePipelinePolicy() async throws {
        dataLoader.steps = [timedOut, timedOut, timedOut]

        _ = try await makePipeline(policy: .immediate(1)).image(for: request(.immediate(3)))

        #expect(dataLoader.requestCount == 4)
    }

    @Test func requestCanOptOutOfThePipelinePolicy() async throws {
        dataLoader.steps = [timedOut]

        await #expect(throws: ImagePipeline.Error.self) {
            _ = try await makePipeline(policy: .immediate()).image(for: request(.disabled))
        }

        #expect(dataLoader.requestCount == 1)
    }

    @Test func requestWithProcessorsUsesItsPolicy() async throws {
        dataLoader.steps = [timedOut]
        var request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "a"), MockImageProcessor(id: "b")])
        request.retryPolicy = .immediate()

        _ = try await makePipeline(policy: nil).image(for: request)

        #expect(dataLoader.requestCount == 2)
    }

    // MARK: - Scheduling

    @Test func waitingForARetryDoesNotHoldASlotInTheQueue() async throws {
        // GIVEN a queue with one slot, and a load waiting for a retry
        dataLoader.steps = [timedOut]
        let pipeline = makePipeline(policy: .waiting) {
            $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 1)
        }
        let waiting = pipeline.imageTask(with: Test.request)
        await waitForRetry(of: waiting)

        // WHEN another load starts, THEN it gets the slot
        _ = try await pipeline.image(for: Test.url.appendingPathComponent("other"))

        #expect(dataLoader.requestCount == 2)
        waiting.cancel()
    }

    @Test func delegateThatSuspendsDoesNotHoldASlotInTheQueue() async throws {
        // GIVEN a queue with one slot, and a delegate that takes its time
        let gate = AsyncGate()
        let isAsked = TestExpectation()
        let delegate = MockRetryDelegate { _ in
            isAsked.fulfill()
            await gate.wait()
            return .stop
        }
        dataLoader.steps = [timedOut]
        let pipeline = makePipeline(delegate: delegate) {
            $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 1)
        }
        let waiting = pipeline.imageTask(with: Test.request)
        await isAsked.wait()

        // WHEN another load starts, THEN it gets the slot
        _ = try await pipeline.image(for: Test.url.appendingPathComponent("other"))

        gate.open()
        #expect(await waiting._task.value.isFailure)
    }

    @Test func retryWaitsForTheDelay() async throws {
        dataLoader.steps = [timedOut]
        let policy = Policy(backoff: .fixed(0.1), jitter: 0, connectivityTimeout: 0)
        let start = ContinuousClock.now

        _ = try await makePipeline(policy: policy).image(for: Test.request)

        #expect(ContinuousClock.now - start >= .milliseconds(100))
        #expect(dataLoader.requestCount == 2)
    }

    @Test(arguments: [TimeInterval.infinity, -1, .nan])
    func delegateCannotCrashThePipelineWithADelay(delay: TimeInterval) async throws {
        let delegate = MockRetryDelegate { _ in .retry(after: delay) }
        dataLoader.steps = [timedOut]
        let task = makePipeline(policy: nil, delegate: delegate).imageTask(with: Test.request)

        if delay == .infinity {
            await waitForRetry(of: task)
            task.cancel()
            _ = await task._task.value
            #expect(dataLoader.requestCount == 1)
        } else {
            _ = try await task.response
            #expect(dataLoader.requestCount == 2)
        }
    }

    @Test func taskCancelledWhileWaitingStopsThere() async throws {
        // GIVEN a load that is going to wait for ten minutes
        dataLoader.steps = [timedOut]
        let pipeline = makePipeline(policy: .waiting)
        let task = pipeline.imageTask(with: Test.request)
        await waitForRetry(of: task)

        // WHEN it is cancelled
        task.cancel()

        // THEN it finishes right away, and that's the end of it
        guard case .failure(.cancelled) = await task._task.value else {
            Issue.record("Expected a cancellation")
            return
        }
        await drainPipeline()
        #expect(dataLoader.requestCount == 1)
        #expect(await pipeline.taskCount == 0)
        #expect(task.status.retryCount == 0)
    }

    @Test func taskCancelledWhileTheDelegateDecidesIsNotRetried() async throws {
        let gate = AsyncGate()
        let isAsked = TestExpectation()
        let delegate = MockRetryDelegate { _ in
            isAsked.fulfill()
            await gate.wait()
            return .retry(after: 0)
        }
        dataLoader.steps = [timedOut]
        let task = makePipeline(delegate: delegate).imageTask(with: Test.request)
        await isAsked.wait()

        task.cancel()
        await waitUntil { task.status.result != nil }
        gate.open()
        await drainPipeline()

        #expect(dataLoader.requestCount == 1)
        #expect(task.status.retryCount == 0)
    }

    @Test func invalidatingThePipelineStopsTheRetries() async throws {
        dataLoader.steps = [timedOut]
        let pipeline = makePipeline(policy: .waiting)
        let task = pipeline.imageTask(with: Test.request)
        await waitForRetry(of: task)

        pipeline.invalidate()

        #expect(await task._task.value.isFailure)
        #expect(dataLoader.requestCount == 1)
    }

    @Test func releasesThePipelineAfterACancelledWait() async throws {
        dataLoader.steps = [timedOut]
        weak var pipelineRef: ImagePipeline?
        do {
            let pipeline = makePipeline(policy: .waiting)
            pipelineRef = pipeline
            let task = pipeline.imageTask(with: Test.request)
            await waitForRetry(of: task)
            task.cancel()
            _ = await task._task.value
        }
        await waitUntil { pipelineRef == nil }
    }

    @Test @ImagePipelineActor func retryGoesBackToTheQueueAtTheCurrentPriority() async throws {
        // GIVEN a load waiting for the delegate to decide
        let gate = AsyncGate()
        let isAsked = TestExpectation()
        let delegate = MockRetryDelegate { _ in
            isAsked.fulfill()
            await gate.wait()
            return .retry(after: 0)
        }
        dataLoader.steps = [timedOut]
        let queue = TaskQueue(maxConcurrentTaskCount: 6)
        var priorities: [TaskPriority] = []
        queue.onEvent = {
            if case .enqueued(let operation) = $0 { priorities.append(operation.priority) }
        }
        let pipeline = makePipeline(delegate: delegate) { $0.dataLoadingQueue = queue }
        let task = pipeline.imageTask(with: Test.request)
        await isAsked.wait()

        // WHEN the priority changes while it waits
        task.priority = .high
        await waitUntil { task.status.priority == .high }
        await drainPipeline()
        gate.open()
        _ = try await task.response

        // THEN the retry uses it
        #expect(priorities == [.normal, .high])
    }

    // MARK: - Coalescing

    @Test func coalescedTasksShareTheRetries() async throws {
        // GIVEN two tasks that wait on the same load
        dataLoader.steps = [timedOut, timedOut]
        dataLoader.isSuspended = true
        let pipeline = makePipeline()
        let first = pipeline.imageTask(with: Test.request)
        let second = pipeline.imageTask(with: Test.request)
        await waitUntil { dataLoader.requestCount == 1 }
        await drainPipeline()

        // WHEN it fails twice
        dataLoader.isSuspended = false
        _ = try await first.response
        _ = try await second.response

        // THEN it's one sequence of retries
        #expect(dataLoader.requestCount == 3)
        #expect(first.status.retryCount == 2)
        #expect(second.status.retryCount == 2)
    }

    @Test func tasksWithDifferentProcessorsShareTheRetries() async throws {
        dataLoader.steps = [timedOut]
        dataLoader.isSuspended = true
        let pipeline = makePipeline()
        let first = pipeline.imageTask(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "a")]))
        let second = pipeline.imageTask(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "b")]))
        await waitUntil { dataLoader.requestCount == 1 }
        await drainPipeline()

        dataLoader.isSuspended = false
        _ = try await first.response
        _ = try await second.response

        #expect(dataLoader.requestCount == 2)
    }

    @Test func tasksJoinALoadThatIsWaitingForARetry() async throws {
        // GIVEN a load waiting for the delegate to decide
        let gate = AsyncGate()
        let isAsked = TestExpectation()
        let delegate = MockRetryDelegate { _ in
            isAsked.fulfill()
            await gate.wait()
            return .retry(after: 0)
        }
        dataLoader.steps = [timedOut]
        let pipeline = makePipeline(delegate: delegate)
        let first = pipeline.imageTask(with: Test.request)
        await isAsked.wait()

        // WHEN another task asks for the same image
        let second = pipeline.imageTask(with: Test.request)
        await drainPipeline()
        gate.open()
        _ = try await first.response
        _ = try await second.response

        // THEN it waits along with the first one
        #expect(dataLoader.requestCount == 2)
        #expect(second.status.retryCount == 1)
    }

    @Test func taskCountsOnlyTheRetriesAfterItJoined() async throws {
        // GIVEN a load that is on its second attempt
        dataLoader.steps = [timedOut, .hold]
        let pipeline = makePipeline()
        let first = pipeline.imageTask(with: Test.request)
        await waitUntil { dataLoader.isHoldingRequest }

        // WHEN another task joins it
        let second = pipeline.imageTask(with: Test.request)
        await drainPipeline()
        dataLoader.resumeHeldRequest()
        _ = try await first.response
        _ = try await second.response

        // THEN it doesn't count what happened before it was there
        #expect(first.status.retryCount == 1)
        #expect(second.status.retryCount == 0)
    }

    @Test func cancellingOneOfTheTasksKeepsTheRetryForTheOther() async throws {
        // GIVEN two tasks that wait for a retry
        let gate = AsyncGate()
        let isAsked = TestExpectation()
        let delegate = MockRetryDelegate { _ in
            isAsked.fulfill()
            await gate.wait()
            return .retry(after: 0)
        }
        dataLoader.steps = [timedOut]
        dataLoader.isSuspended = true
        let pipeline = makePipeline(delegate: delegate)
        let first = pipeline.imageTask(with: Test.request)
        let second = pipeline.imageTask(with: Test.request)
        await waitUntil { dataLoader.requestCount == 1 }
        await drainPipeline()
        dataLoader.isSuspended = false
        await isAsked.wait()

        // WHEN one is cancelled
        first.cancel()
        await waitUntil { first.status.result != nil }
        gate.open()

        // THEN the other gets the image
        _ = try await second.response
        #expect(dataLoader.requestCount == 2)
    }

    @Test func sharedLoadUsesThePolicyThatAllowsTheMostRetries() async throws {
        // GIVEN a task that doesn't want retries, and one that wants them, in
        // both orders
        for policies: [Policy] in [[.disabled, .immediate(2)], [.immediate(2), .disabled]] {
            let dataLoader = MockScriptedDataLoader(steps: [timedOut, timedOut])
            dataLoader.isSuspended = true
            let pipeline = ImagePipeline {
                $0.dataLoader = dataLoader
                $0.imageCache = nil
            }
            let first = pipeline.imageTask(with: request(policies[0]))
            let second = pipeline.imageTask(with: request(policies[1]))
            await waitUntil { dataLoader.requestCount == 1 }
            await drainPipeline()

            // WHEN the load fails
            dataLoader.isSuspended = false
            _ = try await first.response
            _ = try await second.response

            // THEN both get what the second attempt produced
            #expect(dataLoader.requestCount == 3)
        }
    }

    // MARK: - Prefetching

    @Test func prefetchingDoesNotUseThePolicyOfThePipeline() async throws {
        dataLoader.steps = [timedOut]
        let prefetcher = ImagePrefetcher(pipeline: makePipeline())
        let completed = TestExpectation()
        prefetcher.didComplete = { completed.fulfill() }

        prefetcher.startPrefetching(with: [Test.url])
        await completed.wait()

        #expect(dataLoader.requestCount == 1)
    }

    @Test func prefetchingUsesThePolicyOfTheRequest() async throws {
        dataLoader.steps = [timedOut]
        let prefetcher = ImagePrefetcher(pipeline: makePipeline(policy: nil))
        let completed = TestExpectation()
        prefetcher.didComplete = { completed.fulfill() }

        prefetcher.startPrefetching(with: [request(.immediate())])
        await completed.wait()

        #expect(dataLoader.requestCount == 2)
    }

    @Test func taskThatJoinedAPrefetchGetsTheRetries() async throws {
        // GIVEN a task that joined a prefetch
        dataLoader.steps = [timedOut]
        dataLoader.isSuspended = true
        let pipeline = makePipeline()
        let prefetcher = ImagePrefetcher(pipeline: pipeline)
        prefetcher.startPrefetching(with: [Test.url])
        await waitUntil { dataLoader.requestCount == 1 }
        let task = pipeline.imageTask(with: Test.request)
        await drainPipeline()

        // WHEN the load fails
        dataLoader.isSuspended = false

        // THEN the policy of the pipeline applies to the task
        _ = try await task.response
        #expect(dataLoader.requestCount == 2)
    }

    // MARK: - Delegate

    @Test func delegateIsAskedAboutEveryFailedAttempt() async throws {
        let delegate = MockRetryDelegate { $0.policy?.decision(for: $0) ?? .stop }
        dataLoader.steps = [timedOut, .fail(URLError(.cannotFindHost))]
        let request = request(nil)

        _ = try await makePipeline(policy: .immediate(2), delegate: delegate).image(for: request)

        let contexts = delegate.contexts
        #expect(contexts.count == 2)
        #expect(contexts.map(\.retryCount) == [0, 1])
        #expect(contexts.map(\.policy) == [.immediate(2), .immediate(2)])
        #expect(contexts.map { ($0.error.dataLoadingError as? URLError)?.code } == [.timedOut, .cannotFindHost])
        #expect(contexts.first?.request.url == Test.url)
    }

    @Test func delegateIsNotAskedWhenNothingFails() async throws {
        let delegate = MockRetryDelegate { _ in .stop }

        _ = try await makePipeline(delegate: delegate).image(for: Test.request)

        #expect(delegate.contexts.isEmpty)
    }

    @Test func delegateCanRetryWithoutAPolicy() async throws {
        let delegate = MockRetryDelegate { $0.retryCount < 3 ? .retry(after: 0) : .stop }
        dataLoader.steps = [timedOut, timedOut, timedOut]

        _ = try await makePipeline(policy: nil, delegate: delegate).image(for: Test.request)

        #expect(dataLoader.requestCount == 4)
        #expect(delegate.contexts.first?.policy == nil)
    }

    @Test func delegateCanRetryWhatThePolicyWouldNot() async throws {
        let delegate = MockRetryDelegate { _ in .retry(after: 0) }
        dataLoader.steps = [.fail(DataLoader.Error.statusCodeUnacceptable(404))]

        _ = try await makePipeline(policy: .disabled, delegate: delegate).image(for: Test.request)

        #expect(dataLoader.requestCount == 2)
    }

    @Test func delegateCanStopWhatThePolicyWouldRetry() async throws {
        let delegate = MockRetryDelegate { _ in .stop }
        dataLoader.steps = [timedOut]

        await #expect(throws: ImagePipeline.Error.self) {
            _ = try await makePipeline(delegate: delegate).image(for: Test.request)
        }

        #expect(dataLoader.requestCount == 1)
    }

    @Test func coalescedFailureAsksTheDelegateOnce() async throws {
        let delegate = MockRetryDelegate { $0.policy?.decision(for: $0) ?? .stop }
        dataLoader.steps = [timedOut]
        dataLoader.isSuspended = true
        let pipeline = makePipeline(delegate: delegate)
        let tasks = (0..<5).map { _ in pipeline.imageTask(with: Test.request) }
        await waitUntil { dataLoader.requestCount == 1 }
        await drainPipeline()

        dataLoader.isSuspended = false
        for task in tasks {
            _ = try await task.response
        }

        #expect(delegate.contexts.count == 1)
    }

    /// The reason the hook is `async`: the second attempt has to go out with
    /// the token the first one made the delegate refresh.
    @Test func refreshedTokenReachesTheRetry() async throws {
        final class Delegate: ImagePipeline.Delegate, @unchecked Sendable {
            let token = Ref("expired")

            func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
                var urlRequest = urlRequest
                urlRequest.setValue(token.value, forHTTPHeaderField: "Authorization")
                return urlRequest
            }

            func retryDecision(for context: ImagePipeline.RetryContext, pipeline: ImagePipeline) async -> ImagePipeline.RetryDecision {
                guard context.statusCode == 401, context.retryCount == 0 else { return .stop }
                try? await Task.sleep(for: .milliseconds(1)) // The refresh
                token.value = "fresh"
                return .retry(after: 0)
            }
        }
        dataLoader.steps = [.fail(DataLoader.Error.statusCodeUnacceptable(401))]

        _ = try await makePipeline(policy: nil, delegate: Delegate()).image(for: Test.request)

        #expect(dataLoader.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["expired", "fresh"])
    }

    @Test func failureInWillLoadDataIsNotRetried() async throws {
        let delegate = MockWillLoadDataDelegate { _ in throw URLError(.timedOut) }

        await #expect(throws: ImagePipeline.Error.self) {
            _ = try await makePipeline(delegate: delegate).image(for: Test.request)
        }

        #expect(delegate.requests.count == 1)
        #expect(dataLoader.requestCount == 0)
    }

    // MARK: - Responses

    /// A real `DataLoader`, where the only way to learn about the headers of a
    /// response it rejected is the task it ran.
    @Test func responseOfARejectedAttemptReachesTheDelegate() async throws {
        let attempts = EventCounter()
        let url = StubURLProtocol.register { stub in
            attempts.increment()
            if attempts.count == 1 {
                stub.respond(statusCode: 503, headers: ["Retry-After": "0"], chunks: [])
            } else {
                stub.respond(chunks: [Test.data])
            }
        }
        let delegate = MockRetryDelegate { $0.policy?.decision(for: $0) ?? .stop }
        let pipeline = makePipeline(policy: .immediate(), delegate: delegate) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            $0.dataLoader = DataLoader(configuration: configuration)
        }

        _ = try await pipeline.image(for: url)

        #expect(attempts.count == 2)
        let context = try #require(delegate.contexts.first)
        #expect(context.statusCode == 503)
        #expect(context.retryAfter == 0)
        #expect((context.response as? HTTPURLResponse)?.statusCode == 503)
    }

    @Test func serverThatAsksToComeBackLaterIsLeftAlone() async throws {
        let attempts = EventCounter()
        let url = StubURLProtocol.register { stub in
            attempts.increment()
            stub.respond(statusCode: 503, headers: ["Retry-After": "3600"], chunks: [])
        }
        let pipeline = makePipeline(policy: .immediate()) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            $0.dataLoader = DataLoader(configuration: configuration)
        }

        await #expect(throws: ImagePipeline.Error.self) {
            _ = try await pipeline.image(for: url)
        }

        #expect(attempts.count == 1)
    }

    // MARK: - Attempts

    @Test func callbacksOfAFinishedAttemptAreIgnored() async throws {
        // GIVEN a failed attempt whose loader isn't done talking, and a retry
        dataLoader.steps = [.failKeepingCallbacks(URLError(.timedOut)), .hold]
        let task = makePipeline().imageTask(with: Test.request)
        await waitUntil { dataLoader.requestCount == 2 && dataLoader.callbacks != nil }
        await drainPipeline()

        // WHEN it delivers more of the old response, and completes again
        let callbacks = try #require(dataLoader.callbacks)
        let response = URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 100, textEncodingName: nil)
        callbacks.didReceiveData(Data("stale".utf8), response)
        callbacks.completion(URLError(.cancelled))
        await drainPipeline()
        await drainPipeline()

        // THEN the retry isn't affected
        await waitUntil { dataLoader.isHoldingRequest }
        dataLoader.resumeHeldRequest()
        let image = try await task.response
        #expect(image.container.data == nil)
        #expect(task.status.progress.completed == Test.data.count)
    }

    // MARK: - Resumable Downloads

    @Test func retryResumesTheDownload() async throws {
        // GIVEN a download that fails halfway through
        let server = MockRangeServer(data: Test.data, validator: ["ETag": "\"v1\""])
        server.steps = [.fail(after: 10000), .serve]
        let pipeline = makePipeline(policy: .immediate()) { $0.dataLoader = server }

        // WHEN
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN the retry asks for the rest of the bytes
        #expect(server.requests.map { $0.value(forHTTPHeaderField: "Range") } == [nil, "bytes=10000-"])
        #expect((response as? HTTPURLResponse)?.statusCode == 206)
        #expect(data == Test.data)
    }

    @Test func retryStartsOverWhenTheServerIgnoresTheRange() async throws {
        // GIVEN a download that fails halfway, and a server that doesn't resume
        let server = MockRangeServer(data: Test.data, validator: ["ETag": "\"v1\""])
        server.steps = [.fail(after: 10000), .ignoreRange]
        let pipeline = makePipeline(policy: .immediate()) { $0.dataLoader = server }

        // WHEN
        let (data, _) = try await pipeline.data(for: Test.request)

        // THEN the failed attempt leaves nothing behind
        #expect(data == Test.data)
    }

    @Test func retryStartsOverWhenTheResponseCannotBeResumed() async throws {
        // GIVEN a download with no validator to resume it with
        let server = MockRangeServer(data: Test.data, validator: [:])
        server.steps = [.fail(after: 10000), .serve]
        let pipeline = makePipeline(policy: .immediate()) { $0.dataLoader = server }

        // WHEN
        let (data, _) = try await pipeline.data(for: Test.request)

        // THEN
        #expect(server.requests.map { $0.value(forHTTPHeaderField: "Range") } == [nil, nil])
        #expect(data == Test.data)
    }

    @Test func attemptThatFailsBeforeTheResponseKeepsTheBytes() async throws {
        // GIVEN a resumed attempt that doesn't get a response
        let server = MockRangeServer(data: Test.data, validator: ["ETag": "\"v1\""])
        server.steps = [.fail(after: 10000), .failBeforeResponse, .serve]
        let pipeline = makePipeline(policy: .immediate(2)) { $0.dataLoader = server }

        // WHEN
        let (data, _) = try await pipeline.data(for: Test.request)

        // THEN the attempt after it still resumes
        #expect(server.requests.map { $0.value(forHTTPHeaderField: "Range") } == [nil, "bytes=10000-", "bytes=10000-"])
        #expect(data == Test.data)
    }

    @Test func failureAfterASecondResumePicksUpFromTheLatestBytes() async throws {
        // GIVEN two attempts that each fail further along
        let server = MockRangeServer(data: Test.data, validator: ["ETag": "\"v1\""])
        server.steps = [.fail(after: 5000), .fail(after: 15000), .serve]
        let pipeline = makePipeline(policy: .immediate(2)) { $0.dataLoader = server }

        // WHEN
        let (data, _) = try await pipeline.data(for: Test.request)

        // THEN
        #expect(server.requests.map { $0.value(forHTTPHeaderField: "Range") } == [nil, "bytes=5000-", "bytes=15000-"])
        #expect(data == Test.data)
    }

    @Test func progressKeepsTheResumedBytes() async throws {
        let server = MockRangeServer(data: Test.data, validator: ["ETag": "\"v1\""])
        server.steps = [.fail(after: 10000), .serve]
        let pipeline = makePipeline(policy: .immediate()) { $0.dataLoader = server }
        let task = pipeline.imageTask(with: Test.request)

        var progress: [ImageTask.Progress] = []
        for await value in task.progress {
            progress.append(value)
        }

        #expect(progress.last == ImageTask.Progress(completed: Int64(Test.data.count), total: Int64(Test.data.count)))
        #expect(progress.allSatisfy { $0.total == Int64(Test.data.count) })
    }

    // MARK: - Progressive Decoding

    /// An incremental decoder expects the data to grow, and the data of a
    /// retry that couldn't resume is shorter than the data it had so far.
    @Test func retryThatStartsOverGetsANewDecoder() async throws {
        // GIVEN a progressive image, and a download that can't be resumed
        let data = Test.data(name: "progressive", extension: "jpeg")
        let server = MockRangeServer(data: data, validator: [:])
        server.chunkSize = 3000
        server.steps = [.fail(after: data.count - 1000), .serve]
        let decoders = EventCounter()
        let pipeline = makePipeline(policy: .immediate()) {
            $0.dataLoader = server
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.makeImageDecoder = { context in
                if !context.isCompleted { decoders.increment() }
                return ImageDecoders.Default(context: context)
            }
        }
        let task = pipeline.imageTask(with: Test.request)

        // WHEN
        var previewCount = 0
        for await event in task.events {
            if case .preview = event { previewCount += 1 }
        }

        // THEN
        #expect(task.status.result?.isSuccess == true)
        #expect(previewCount > 0)
        #expect(decoders.count >= 2)
    }

    /// The size can't tell a retry that started over: the first chunk here is
    /// as large as everything the failed attempt delivered.
    @Test func retryThatStartsOverGetsANewDecoderWhateverTheSizeOfTheData() async throws {
        // GIVEN a download that fails after one chunk, and can't be resumed
        let data = Test.data(name: "progressive", extension: "jpeg")
        let server = MockRangeServer(data: data, validator: [:])
        server.chunkSize = 3000
        server.steps = [.fail(after: 3000), .serve]
        let decoders = EventCounter()
        let pipeline = makePipeline(policy: .immediate()) {
            $0.dataLoader = server
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.makeImageDecoder = { context in
                if !context.isCompleted { decoders.increment() }
                return ImageDecoders.Default(context: context)
            }
        }

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN
        #expect(decoders.count == 2)
    }

    @Test func retryThatResumesKeepsTheDecoder() async throws {
        // GIVEN a progressive image, and a download that can be resumed
        let data = Test.data(name: "progressive", extension: "jpeg")
        let server = MockRangeServer(data: data, validator: ["ETag": "\"v1\""])
        server.chunkSize = 3000
        server.steps = [.fail(after: data.count / 2), .serve]
        let decoders = EventCounter()
        let pipeline = makePipeline(policy: .immediate()) {
            $0.dataLoader = server
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.makeImageDecoder = { context in
                if !context.isCompleted { decoders.increment() }
                return ImageDecoders.Default(context: context)
            }
        }

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN
        #expect(decoders.count == 1)
    }

    // MARK: - Connectivity

    private func makeOfflinePipeline(_ observer: MockConnectivityObserver, policy: Policy) -> ImagePipeline {
        let pipeline = makePipeline(policy: policy)
        pipeline.connectivityMonitor = ConnectivityMonitor { observer }
        return pipeline
    }

    private var offlinePolicy: Policy {
        Policy(backoff: .fixed(0), jitter: 0, connectivityTimeout: 60)
    }

    @Test func offlineLoadWaitsForTheDeviceToGetBackOnline() async throws {
        // GIVEN a load that failed because the device is offline
        let observer = MockConnectivityObserver(isOnline: false)
        dataLoader.steps = [.fail(URLError(.notConnectedToInternet))]
        let task = makeOfflinePipeline(observer, policy: offlinePolicy).imageTask(with: Test.request)
        await waitUntil { observer.startCount == 1 }
        await drainPipeline()
        #expect(dataLoader.requestCount == 1)

        // WHEN it gets back online
        observer.isOnline = true

        // THEN the load goes through
        _ = try await task.response
        #expect(dataLoader.requestCount == 2)
    }

    @Test func offlineLoadDoesNotHoldASlotInTheQueue() async throws {
        let observer = MockConnectivityObserver(isOnline: false)
        dataLoader.steps = [.fail(URLError(.notConnectedToInternet))]
        let pipeline = makePipeline(policy: offlinePolicy) {
            $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 1)
        }
        pipeline.connectivityMonitor = ConnectivityMonitor { observer }
        let waiting = pipeline.imageTask(with: Test.request)
        await waitUntil { observer.startCount == 1 }

        _ = try await pipeline.image(for: Test.url.appendingPathComponent("other"))

        waiting.cancel()
    }

    @Test func offlineLoadFailsWithTheOriginalErrorWhenTheTimeRunsOut() async throws {
        // GIVEN a device that stays offline
        let observer = MockConnectivityObserver(isOnline: false)
        dataLoader.steps = [.fail(URLError(.notConnectedToInternet))]
        let policy = Policy(backoff: .fixed(0), jitter: 0, connectivityTimeout: 0.01)
        let task = makeOfflinePipeline(observer, policy: policy).imageTask(with: Test.request)

        // WHEN
        let result = await task._task.value

        // THEN it doesn't spend another attempt on it
        guard case .failure(.dataLoadingFailed(let error as URLError)) = result else {
            Issue.record("Unexpected result: \(result)")
            return
        }
        #expect(error.code == .notConnectedToInternet)
        #expect(dataLoader.requestCount == 1)
        #expect(task.status.retryCount == 0)
    }

    @Test func offlineLoadCancelledWhileWaitingStopsThere() async throws {
        let observer = MockConnectivityObserver(isOnline: false)
        dataLoader.steps = [.fail(URLError(.notConnectedToInternet))]
        let task = makeOfflinePipeline(observer, policy: offlinePolicy).imageTask(with: Test.request)
        await waitUntil { observer.startCount == 1 }

        task.cancel()

        guard case .failure(.cancelled) = await task._task.value else {
            Issue.record("Expected a cancellation")
            return
        }
        await waitUntil { observer.stopCount == 1 }
        #expect(dataLoader.requestCount == 1)
    }

    @Test func loadCanWaitForAsLongAsItTakes() async throws {
        let observer = MockConnectivityObserver(isOnline: false)
        dataLoader.steps = [.fail(URLError(.notConnectedToInternet))]
        let policy = Policy(backoff: .fixed(0), jitter: 0, connectivityTimeout: .infinity)
        let task = makeOfflinePipeline(observer, policy: policy).imageTask(with: Test.request)
        await waitUntil { observer.startCount == 1 }

        observer.isOnline = true

        _ = try await task.response
    }

    @Test func delegateCanWaitForConnectivity() async throws {
        let observer = MockConnectivityObserver(isOnline: false)
        let delegate = MockRetryDelegate { _ in .retryWhenOnline(after: 0, timeout: 60) }
        dataLoader.steps = [.fail(URLError(.timedOut))]
        let pipeline = makePipeline(policy: nil, delegate: delegate)
        pipeline.connectivityMonitor = ConnectivityMonitor { observer }
        let task = pipeline.imageTask(with: Test.request)
        await waitUntil { observer.startCount == 1 }

        observer.isOnline = true

        _ = try await task.response
        #expect(dataLoader.requestCount == 2)
    }

    // MARK: - Diagnostics

    @Test func metricsRecordTheAttempts() async throws {
        // GIVEN
        dataLoader.steps = [.fail(DataLoader.Error.statusCodeUnacceptable(503))]
        let policy = Policy(backoff: .fixed(0.01), jitter: 0, connectivityTimeout: 0)
        let pipeline = makePipeline(policy: policy) { $0.isDiagnosticsEnabled = true }
        let task = pipeline.imageTask(with: Test.request)

        // WHEN
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.outcome == .success)
        #expect(metrics.retryCount == 1)
        #expect(metrics.source == .network)
        #expect(metrics.bytes?.downloaded == Int64(Test.data.count))

        let job = try #require(metrics.jobs.first { $0.kind == .fetchOriginalData })
        let stages = job.stages.filter { $0.kind != .diskLookup && $0.kind != .diskStore }
        #expect(stages.map(\.kind) == [.download, .retryDelay, .download])
        #expect(stages[0].error?.code == "dataLoadingFailed")
        #expect(stages[2].error == nil)

        let delay = try #require(stages[1].duration)
        #expect(delay >= 0.009)

        let share = try #require(metrics.timeShares.first { $0.category == .retry })
        #expect(share.duration >= 0.009)

        let timeline = metrics.formatted(.timeline)
        #expect(timeline.contains("retryDelay"))
        #expect(timeline.contains("dataLoadingFailed"))
    }

    @Test func metricsDoNotCountAWaitThatEndedWithoutARetry() async throws {
        let observer = MockConnectivityObserver(isOnline: false)
        dataLoader.steps = [.fail(URLError(.notConnectedToInternet))]
        let policy = Policy(backoff: .fixed(0), jitter: 0, connectivityTimeout: 0.01)
        let pipeline = makePipeline(policy: policy) { $0.isDiagnosticsEnabled = true }
        pipeline.connectivityMonitor = ConnectivityMonitor { observer }
        let task = pipeline.imageTask(with: Test.request)

        #expect(await task._task.value.isFailure)

        let metrics = try #require(task.metrics)
        #expect(metrics.retryCount == 0)
        #expect(metrics.jobs.flatMap(\.stages).contains { $0.kind == .retryDelay })
    }

    @Test func summaryMentionsTheRetries() async throws {
        dataLoader.steps = [timedOut, timedOut]
        let pipeline = makePipeline(policy: .immediate(2)) { $0.isDiagnosticsEnabled = true }
        let task = pipeline.imageTask(with: Test.request)

        _ = try await task.response

        #expect(try #require(task.metrics).summary.hasSuffix(" · 2 retries"))
    }

    @Test func summaryOfAFailedLoadMentionsTheRetries() async throws {
        dataLoader.steps = [timedOut, timedOut]
        let pipeline = makePipeline(policy: .immediate(1)) { $0.isDiagnosticsEnabled = true }
        let task = pipeline.imageTask(with: Test.request)

        #expect(await task._task.value.isFailure)

        #expect(try #require(task.metrics).summary.hasSuffix(" · 1 retry"))
    }

    @Test func snapshotSaysThatTheLoadIsWaitingToRetry() async throws {
        // GIVEN a load that is waiting to retry, with nothing in the queues
        dataLoader.steps = [timedOut]
        let pipeline = makePipeline(policy: .waiting)
        let task = pipeline.imageTask(with: Test.request)
        await waitForRetry(of: task)

        // WHEN
        let snapshot = await pipeline.diagnostics.snapshot()

        // THEN it doesn't look stuck
        let active = try #require(snapshot.tasks.first)
        #expect(active.isWaitingForRetry)
        #expect(active.retryCount == 0)
        #expect(snapshot.queues.allSatisfy { $0.runningCount == 0 })
        #expect(snapshot.description.contains("waiting to retry"))
        task.cancel()
    }

    @Test func snapshotDoesNotReportAWaitThatIsOver() async throws {
        // GIVEN a retry that is running
        dataLoader.steps = [timedOut, .hold]
        let pipeline = makePipeline()
        let task = pipeline.imageTask(with: Test.request)
        await waitUntil { dataLoader.isHoldingRequest }

        // WHEN
        let snapshot = await pipeline.diagnostics.snapshot()

        // THEN
        let active = try #require(snapshot.tasks.first)
        #expect(!active.isWaitingForRetry)
        #expect(active.retryCount == 1)
        #expect(snapshot.description.contains("1 retry"))
        task.cancel()
    }

    @Test func metricsOfAFailedLoadRecordEveryFailure() async throws {
        dataLoader.steps = [timedOut, timedOut, timedOut]
        let pipeline = makePipeline(policy: .immediate(1)) { $0.isDiagnosticsEnabled = true }
        let task = pipeline.imageTask(with: Test.request)

        #expect(await task._task.value.isFailure)

        let metrics = try #require(task.metrics)
        #expect(metrics.outcome == .failure)
        #expect(metrics.retryCount == 1)
        let job = try #require(metrics.jobs.first { $0.kind == .fetchOriginalData })
        #expect(job.stages.filter { $0.kind == .download }.compactMap(\.error).count == 2)
    }

    @Test func metricsOfAClosureRecordTheFailure() async throws {
        let attempts = EventCounter()
        let request = ImageRequest(id: "a", image: {
            attempts.increment()
            if attempts.count == 1 { throw URLError(.timedOut) }
            return ImageContainer(image: Test.image)
        })
        let pipeline = makePipeline { $0.isDiagnosticsEnabled = true }
        let task = pipeline.imageTask(with: request)

        _ = try await task.response

        let metrics = try #require(task.metrics)
        #expect(metrics.retryCount == 1)
        let job = try #require(metrics.jobs.first { $0.kind == .fetchOriginalImage })
        #expect(job.stages.filter { $0.kind == .download }.map { $0.error?.code } == ["dataLoadingFailed", nil])
    }

    @Test func metricsWithARejectedResponseHaveTheStatusCode() async throws {
        let attempts = EventCounter()
        let url = StubURLProtocol.register { stub in
            attempts.increment()
            if attempts.count == 1 {
                stub.respond(statusCode: 503, chunks: [])
            } else {
                stub.respond(chunks: [Test.data])
            }
        }
        let pipeline = makePipeline(policy: .immediate()) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            $0.dataLoader = DataLoader(configuration: configuration)
            $0.isDiagnosticsEnabled = true
        }
        let task = pipeline.imageTask(with: url)

        _ = try await task.response

        let metrics = try #require(task.metrics)
        let downloads = try #require(metrics.jobs.first { $0.kind == .fetchOriginalData }).stages.filter { $0.kind == .download }
        #expect(downloads.map(\.statusCode) == [503, 200])
    }

    @Test func metricsReportTheSessionMetricsOfTheLastAttempt() async throws {
        let attempts = EventCounter()
        let url = StubURLProtocol.register { stub in
            attempts.increment()
            if attempts.count == 1 {
                stub.fail(URLError(.timedOut))
            } else {
                stub.respond(chunks: [Test.data])
            }
        }
        let pipeline = makePipeline(policy: .immediate()) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            $0.dataLoader = DataLoader(configuration: configuration)
            $0.isDiagnosticsEnabled = true
        }
        let task = pipeline.imageTask(with: url)

        _ = try await task.response

        let metrics = try #require(task.metrics)
        let downloads = try #require(metrics.jobs.first { $0.kind == .fetchOriginalData }).stages.filter { $0.kind == .download }
        #expect(downloads.compactMap(\.urlSessionMetrics).count == 2)
        #expect(metrics.urlSessionMetrics?.urlSessionTaskID == downloads.last?.urlSessionTaskID)
    }

    @Test func metricsSurviveEncoding() async throws {
        dataLoader.steps = [timedOut]
        let pipeline = makePipeline { $0.isDiagnosticsEnabled = true }
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response
        let metrics = try #require(task.metrics)

        let decoded = try JSONDecoder().decode(ImageTask.Metrics.self, from: JSONEncoder().encode(metrics))

        #expect(decoded.retryCount == 1)
        #expect(decoded.jobs.flatMap(\.stages).contains { $0.error?.code == "dataLoadingFailed" })
    }
}
