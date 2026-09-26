// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

// The requests in this file are served by `StubURLProtocol`, which looks up a
// handler registered under a unique URL for every test, so these suites don't
// need to be serialized.

// MARK: - Loading Contract

/// The `DataLoading` contract as ``DataLoader`` implements it on top of
/// `URLSession`: one completion per load, no data after a rejection or a
/// cancellation, and a session that goes away with the loader.
@Suite(.timeLimit(.minutes(5)))
struct DataLoaderSessionContractTests {

    // MARK: Configuration

    @Test func sessionUsesTheGivenConfigurationAndASerialDelegateQueue() {
        // Given
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 42

        // When
        let loader = DataLoader(configuration: configuration)

        // Then
        #expect(loader.session.configuration.timeoutIntervalForRequest == 42)
        #expect(loader.session.sessionDescription == "Nuke URLSession")
        // The loader tracks its tasks without a lock, which is only safe
        // because `URLSession` calls the delegate on a serial queue.
        #expect(loader.session.delegateQueue.maxConcurrentOperationCount == 1)
        #expect(loader.session.delegate is URLSessionDataDelegate)
    }

    @Test func defaultConfigurationIsAFreshInstanceEveryTime() {
        // Given
        let first = DataLoader.defaultConfiguration
        first.timeoutIntervalForRequest = 1

        // When
        let second = DataLoader.defaultConfiguration

        // Then modifying one doesn't affect the loaders created later
        #expect(first !== second)
        #expect(second.timeoutIntervalForRequest != 1)
    }

    @Test func defaultConfigurationHasUrlCache() {
        #expect(DataLoader.defaultConfiguration.urlCache === DataLoader.sharedUrlCache)
    }

    @Test func sharedUrlCacheHasExpectedCapacity() {
        let cache = DataLoader.sharedUrlCache
        #expect(cache.memoryCapacity == 0)
        #expect(cache.diskCapacity == 150 * 1048576)
    }

    // MARK: Requests

    /// The range headers that resume a partial download must reach the
    /// server along with the rest of the request, and the server's
    /// "206 Partial Content" must pass the default validation.
    @Test func resumingRequestIsSentAsIs() async throws {
        // Given a server that records the request
        let sent = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
        let url = StubURLProtocol.register { stub in
            sent.withLock { $0 = stub.request }
            stub.respond(statusCode: 206, chunks: [Data("tail".utf8)])
        }

        // Given a request resuming a partial download
        let partialResponse = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Accept-Ranges": "bytes",
            "Content-Length": "8",
            "ETag": "\"v1\""
        ]))
        let resumableData = try #require(ResumableData(response: partialResponse, data: Data("head".utf8)))
        var request = URLRequest(url: url)
        request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
        resumableData.resume(request: &request)

        // When
        let loader = makeStubLoader()
        let recorder = LoadRecorder()
        let cancellable = recorder.load(with: loader, request: request)
        await recorder.completed.wait()

        // Then the server receives every header
        let request2 = try #require(sent.withLock { $0 })
        #expect(request2.value(forHTTPHeaderField: "Range") == "bytes=4-")
        #expect(request2.value(forHTTPHeaderField: "If-Range") == "\"v1\"")
        #expect(request2.value(forHTTPHeaderField: "Authorization") == "Bearer token")

        // Then the partial response is accepted
        #expect(recorder.error == nil)
        #expect(recorder.body == Data("tail".utf8))
        #expect((recorder.responses.first as? HTTPURLResponse)?.statusCode == 206)

        // Then the handle wraps the task that performed the request
        let handle = try #require(cancellable as? URLSessionTaskCancellable)
        #expect(handle.task.originalRequest?.url == url)
    }

    /// `prefersIncrementalDelivery` is read when each task is created, so a
    /// change applies to the loads started after it.
    @Test func prefersIncrementalDeliveryIsAppliedToEachNewTask() async {
        // Given
        let observed = OSAllocatedUnfairLock<[Bool?]>(initialState: [])
        let url = StubURLProtocol.register { stub in
            observed.withLock { $0.append(stub.task?.prefersIncrementalDelivery) }
            stub.respond(chunks: [Data("x".utf8)])
        }
        let loader = makeStubLoader()
        #expect(!loader.prefersIncrementalDelivery) // The default

        // When
        loader.prefersIncrementalDelivery = true
        await LoadRecorder().loadToCompletion(with: loader, request: URLRequest(url: url))
        loader.prefersIncrementalDelivery = false
        await LoadRecorder().loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(observed.withLock { $0 } == [true, false])
    }

    /// The loader reads `prefersIncrementalDelivery` when each task is created,
    /// which happens on the thread that starts the request, so writing it from
    /// another thread has to be synchronized – otherwise the thread sanitizer
    /// aborts the test run.
    @Test func prefersIncrementalDeliveryIsToggledWhileLoadingData() async {
        // Given
        let loader = makeStubLoader()
        let urls = (0..<50).map { _ in
            StubURLProtocol.register { $0.respond(chunks: [Data("x".utf8)]) }
        }

        let writer = Task.detached {
            var isEnabled = true
            while !Task.isCancelled {
                isEnabled.toggle()
                loader.prefersIncrementalDelivery = isEnabled
                await Task.yield()
            }
        }

        // When loading data while the flag is being toggled
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    let recorder = LoadRecorder()
                    await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))
                    #expect(recorder.error == nil)
                    #expect(recorder.body == Data("x".utf8))
                }
            }
        }

        // Then no data races are reported
        writer.cancel()
        await writer.value
    }

    @Test func pipelineRequestsIncrementalDeliveryOnlyForProgressiveDecoding() {
        // Given
        let loader = makeStubLoader()

        // When
        _ = ImagePipeline {
            $0.dataLoader = loader
            $0.isProgressiveDecodingEnabled = true
        }

        // Then
        #expect(loader.prefersIncrementalDelivery)

        // When
        _ = ImagePipeline {
            $0.dataLoader = loader
            $0.isProgressiveDecodingEnabled = false
        }

        // Then
        #expect(!loader.prefersIncrementalDelivery)
    }

    @Test func dataURLIsLoadedWithoutHTTPValidation() async throws {
        // Given a URL that `URLSession` serves without HTTP
        let url = try #require(URL(string: "data:text/plain;base64,aGVsbG8="))

        // When
        let loader = makeStubLoader()
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then the default validation lets a non-HTTP response through
        #expect(recorder.error == nil)
        #expect(recorder.body == Data("hello".utf8))
        let response = try #require(recorder.responses.first)
        #expect(!(response is HTTPURLResponse))
        #expect(response.mimeType == "text/plain")
    }

    // MARK: Responses

    @Test func loadMultipleChunks() async throws {
        // Given
        let chunks = [Data("aaa".utf8), Data("bbb".utf8), Data("ccc".utf8)]
        let url = StubURLProtocol.register { $0.respond(chunks: chunks) }
        let loader = makeStubLoader()

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(recorder.error == nil)
        #expect(recorder.body == Data("aaabbbccc".utf8))
        let response = try #require(recorder.responses.first as? HTTPURLResponse)
        #expect(response.statusCode == 200)
    }

    @Test func loadEmptyBody() async {
        // Given
        let url = StubURLProtocol.register { $0.respond(chunks: []) }
        let loader = makeStubLoader()

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(recorder.error == nil)
        #expect(recorder.chunks.isEmpty)
    }

    @Test func responseHeadersAreDelivered() async throws {
        // Given
        let url = StubURLProtocol.register { $0.respond(headers: ["X-Custom": "value123"], chunks: [Data("x".utf8)]) }
        let loader = makeStubLoader()

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        let response = try #require(recorder.responses.first as? HTTPURLResponse)
        #expect(response.value(forHTTPHeaderField: "X-Custom") == "value123")
    }

    @Test func loadLargeData() async {
        // Given a 1 MB body sent in 100 KB chunks
        let body = Data(repeating: 0xAB, count: 1_000_000)
        let chunks = _createChunks(for: body, size: 100_000)
        let url = StubURLProtocol.register { $0.respond(chunks: chunks) }
        let loader = makeStubLoader()

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(recorder.error == nil)
        #expect(recorder.body == body)
    }

    @Test func concurrentLoads() async {
        // Given
        let loader = makeStubLoader()
        let urls = (0..<5).map { index in
            StubURLProtocol.register { $0.respond(chunks: [Data("response-\(index)".utf8)]) }
        }

        // When/Then each load gets the response to its own request
        await withTaskGroup(of: Void.self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let recorder = LoadRecorder()
                    await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))
                    #expect(recorder.body == Data("response-\(index)".utf8))
                }
            }
        }
    }

    @Test func errorBeforeResponse() async {
        // Given a server that can't be reached
        let url = StubURLProtocol.register { $0.fail(URLError(.cannotFindHost)) }
        let loader = makeStubLoader()

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect((recorder.error as? URLError)?.code == .cannotFindHost)
    }

    // MARK: Validation

    /// `DataLoading` requires no data to follow a failure, so the body of a
    /// rejected response must never reach `didReceiveData`.
    @Test func rejectedResponseDeliversNoData() async throws {
        // Given
        let url = StubURLProtocol.register { stub in
            stub.respond(statusCode: 404, headers: ["X-Reason": "missing"], chunks: [Data("not ".utf8), Data("found".utf8)])
        }
        let validated = OSAllocatedUnfairLock<[String?]>(initialState: [])
        let loader = makeStubLoader { response in
            validated.withLock { $0.append((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Reason")) }
            return DataLoader.validate(response: response)
        }
        let delegate = EventLoggingDelegate()
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        _ = recorder.load(with: loader, request: URLRequest(url: url))
        await recorder.completed.wait()
        await delegate.didComplete.wait()
        await loader.drainDelegateQueue()

        // Then the response is validated exactly once
        #expect(validated.withLock { $0 } == ["missing"])

        // Then the load fails without delivering the body
        #expect(recorder.chunks.isEmpty)
        #expect(recorder.completionCount == 1)
        let error = try #require(recorder.error as? DataLoader.Error)
        guard case .statusCodeUnacceptable(404) = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
    }

    @Test func pipelineReportsRejectedResponseAsDataLoadingFailure() async throws {
        // Given
        let url = StubURLProtocol.register { $0.respond(statusCode: 404, chunks: [Data("not found".utf8)]) }
        let loader = makeStubLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = loader
            $0.imageCache = nil
        }

        // When
        do {
            _ = try await pipeline.image(for: url)
            Issue.record("Expected the load to fail")
        } catch {
            // Then
            guard case .dataLoadingFailed(let underlying) = error,
                  case .statusCodeUnacceptable(404)? = underlying as? DataLoader.Error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test(arguments: [100, 199, 300, 304, 399, 400, 599])
    func defaultValidationRejectsStatusCodesOutside2xx(statusCode: Int) throws {
        let response = try #require(HTTPURLResponse(url: Test.url, statusCode: statusCode, httpVersion: nil, headerFields: nil))
        let error = try #require(DataLoader.validate(response: response) as? DataLoader.Error)
        guard case .statusCodeUnacceptable(let code) = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
        #expect(code == statusCode)
    }

    @Test func staticValidateAccepts200() throws {
        let response = try #require(HTTPURLResponse(url: Test.url, statusCode: 200, httpVersion: nil, headerFields: nil))
        #expect(DataLoader.validate(response: response) == nil)
    }

    @Test(arguments: [200, 201, 204, 299])
    func validationAccepts2xxRange(statusCode: Int) async {
        // Given
        let url = StubURLProtocol.register { $0.respond(statusCode: statusCode, chunks: [Data("ok".utf8)]) }
        let loader = makeStubLoader()

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(recorder.error == nil)
        #expect((recorder.responses.first as? HTTPURLResponse)?.statusCode == statusCode)
    }

    /// The initializer validates the status code unless told otherwise.
    @Test func initWithDefaultValidationRejectsNon2xx() async {
        // Given a loader created without a `validate` closure
        let url = StubURLProtocol.register { $0.respond(statusCode: 403, chunks: [Data("forbidden".utf8)]) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let loader = DataLoader(configuration: configuration)

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(recorder.error is DataLoader.Error)
    }

    @Test func customValidation() async {
        // Given
        struct CustomError: Error {}
        let url = StubURLProtocol.register { $0.respond(chunks: [Data("ok".utf8)]) }
        let loader = makeStubLoader { _ in CustomError() }

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(recorder.error is CustomError)
    }

    @Test func noValidationPassesEverything() async {
        // Given
        let url = StubURLProtocol.register { $0.respond(statusCode: 500, chunks: [Data("ok".utf8)]) }
        let loader = makeStubLoader { _ in nil }

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(recorder.error == nil)
        #expect((recorder.responses.first as? HTTPURLResponse)?.statusCode == 500)
    }

    @Test func errorDescription() {
        let error = DataLoader.Error.statusCodeUnacceptable(404)
        #expect(error.description.contains("404"))
    }

    // MARK: Cancellation

    /// The handler is registered on the delegate queue before the task is
    /// resumed, so even a load cancelled right away finds it and completes.
    /// The pipeline depends on this completion: it's what gives the download's
    /// `dataLoadingQueue` slot back.
    @Test func cancellingRightAwayCompletesOnceWithCancelledError() async {
        // Given a server that never responds
        let url = StubURLProtocol.register { _ in }
        let loader = makeStubLoader()

        // When
        let recorder = LoadRecorder()
        recorder.load(with: loader, request: URLRequest(url: url)).cancel()
        await recorder.completed.wait()
        await loader.drainDelegateQueue()

        // Then
        #expect(recorder.completionCount == 1)
        #expect((recorder.error as? URLError)?.code == .cancelled)
        #expect(recorder.chunks.isEmpty)
    }

    @Test func cancellingMidBodyCompletesOnceWithCancelledError() async {
        // Given a server that sends a part of the body and stalls. `URLSession`
        // holds back a first chunk of only a few bytes (it sniffs the content
        // type), so the part is 1 KB.
        let part = Data(repeating: 1, count: 1024)
        let url = StubURLProtocol.register { stub in
            stub.sendResponse(headers: ["Content-Length": "4096"])
            stub.send(part)
        }
        let loader = makeStubLoader()

        // When
        let recorder = LoadRecorder()
        let task = recorder.load(with: loader, request: URLRequest(url: url))
        await recorder.receivedData.wait()
        task.cancel()
        await recorder.completed.wait()
        await loader.drainDelegateQueue()

        // Then
        #expect(recorder.body == part)
        #expect(recorder.completionCount == 1)
        #expect((recorder.error as? URLError)?.code == .cancelled)
    }

    @Test func cancellingAfterCompletionHasNoEffect() async {
        // Given a completed load
        let url = StubURLProtocol.register { $0.respond(chunks: [Data("done".utf8)]) }
        let loader = makeStubLoader()
        let recorder = LoadRecorder()
        let task = recorder.load(with: loader, request: URLRequest(url: url))
        await recorder.completed.wait()

        // When
        task.cancel()
        task.cancel()
        await loader.drainDelegateQueue()

        // Then
        #expect(recorder.completionCount == 1)
        #expect(recorder.error == nil)
        #expect(recorder.body == Data("done".utf8))
    }

    /// Loads are tracked per task, so two loads of the same URL on the same
    /// loader don't interfere: cancelling one leaves the other intact.
    @Test func loadsOfTheSameURLAreTrackedSeparately() async {
        // Given a server that stalls the first request and answers the second
        let stalled = TestExpectation()
        let url = StubURLProtocol.register { stub in
            if stub.request.value(forHTTPHeaderField: "X-Load") == "slow" {
                stub.sendResponse()
                stalled.fulfill()
            } else {
                stub.respond(chunks: [Data("fast".utf8)])
            }
        }
        let loader = makeStubLoader()
        var slowRequest = URLRequest(url: url)
        slowRequest.setValue("slow", forHTTPHeaderField: "X-Load")

        // When
        let slow = LoadRecorder()
        let slowTask = slow.load(with: loader, request: slowRequest)
        await stalled.wait()
        let fast = LoadRecorder()
        await fast.loadToCompletion(with: loader, request: URLRequest(url: url))
        slowTask.cancel()
        await slow.completed.wait()

        // Then
        #expect(fast.error == nil)
        #expect(fast.body == Data("fast".utf8))
        #expect((slow.error as? URLError)?.code == .cancelled)
        #expect(slow.chunks.isEmpty)
    }

    /// The loader isn't retained by its session or its tasks, and releasing it
    /// cancels the loads in flight instead of leaving them hanging.
    @Test func releasingTheLoaderCancelsItsLoads() async {
        // Given a server that stalls after the response
        let started = TestExpectation()
        let url = StubURLProtocol.register { stub in
            stub.sendResponse(headers: ["Content-Length": "100"])
            started.fulfill()
        }
        let recorder = LoadRecorder()
        weak var weakLoader: DataLoader?
        do {
            let loader = makeStubLoader()
            weakLoader = loader
            _ = recorder.load(with: loader, request: URLRequest(url: url))
            await started.wait()
        }

        // Then
        #expect(weakLoader == nil)
        await recorder.completed.wait()
        #expect(recorder.completionCount == 1)
        #expect((recorder.error as? URLError)?.code == .cancelled)
    }

    // MARK: Session Events

    /// `didReceiveData` must carry a response, so a chunk that the session
    /// delivers before any response is dropped; the load still completes.
    @Test func chunkWithoutResponseIsNotDelivered() async {
        // Given a server that skips the response
        let url = StubURLProtocol.register { stub in
            stub.send(Data("orphan".utf8))
            stub.finish()
        }

        // When
        let loader = makeStubLoader()
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(recorder.chunks.isEmpty)
        #expect(recorder.completionCount == 1)
        #expect(recorder.error == nil)
    }

    /// The loader only lets its own loads run: a task started directly on its
    /// session has nobody to deliver the data to, so it's cancelled as soon as
    /// the response arrives.
    @Test func taskStartedDirectlyOnTheSessionIsCancelledOnResponse() async {
        // Given
        let url = StubURLProtocol.register { $0.respond(chunks: [Data("unused".utf8)]) }
        let loader = makeStubLoader()
        let delegate = EventLoggingDelegate()
        loader.delegate = delegate

        // When
        loader.session.dataTask(with: url).resume()
        await delegate.didComplete.wait()

        // Then
        #expect(delegate.events.contains("response 200"))
        #expect(!delegate.events.contains("data"))
        #expect(delegate.events.last == "complete \(URLError.Code.cancelled.rawValue)")
    }

    @Test func metricsAreDeliveredWithTheCompletionWhenAskedFor() async throws {
        // Given
        let url = StubURLProtocol.register { $0.respond(chunks: [Data("data".utf8)]) }
        let loader = makeStubLoader()

        // When
        let metrics: URLSessionTaskMetrics? = await withCheckedContinuation { continuation in
            _ = loader.loadData(with: URLRequest(url: url), didReceiveData: { _, _ in }) { _, metrics in
                continuation.resume(returning: metrics)
            }
        }

        // Then
        let collected = try #require(metrics)
        #expect(collected.transactionMetrics.count == 1)
        #expect(collected.transactionMetrics.first?.request.url == url)
    }

    /// The diagnostics rely on the metrics of a failed download too.
    @Test func metricsAreDeliveredWhenTheLoadFails() async {
        // Given a server that drops the connection mid-body
        let url = StubURLProtocol.register { stub in
            stub.sendResponse(headers: ["Content-Length": "100"])
            stub.send(Data("partial".utf8))
            stub.fail(URLError(.networkConnectionLost))
        }
        let loader = makeStubLoader()

        // When
        let (code, metrics) = await withCheckedContinuation { continuation in
            _ = loader.loadData(with: URLRequest(url: url), didReceiveData: { _, _ in }) { error, metrics in
                continuation.resume(returning: ((error as? URLError)?.code, metrics))
            }
        }

        // Then
        #expect(code == .networkConnectionLost)
        #expect(metrics?.transactionMetrics.first?.request.url == url)
    }
}

// MARK: - Delegate Forwarding

/// ``DataLoader/delegate`` observes the session events and can make the
/// decisions that `URLSession` asks its delegate for; without one, the loader
/// falls back to the system defaults.
@Suite(.timeLimit(.minutes(5)))
struct DataLoaderDelegateForwardingTests {

    // MARK: Event Order

    @Test func delegateHearsAboutEachEventBeforeTheLoader() async {
        // Given
        let url = StubURLProtocol.register { $0.respond(chunks: [Data("body".utf8)]) }
        let loader = makeStubLoader()
        let delegate = EventLoggingDelegate()
        loader.delegate = delegate

        // When
        let completed = TestExpectation()
        _ = loader.loadData(
            with: URLRequest(url: url),
            didReceiveData: { _, _ in delegate.log("loader: data") },
            completion: { _ in
                delegate.log("loader: completion")
                completed.fulfill()
            }
        )
        await completed.wait()

        // Then
        #expect(delegate.events == [
            "didCreateTask",
            "response 200",
            "data",
            "loader: data",
            "metrics",
            "complete",
            "loader: completion"
        ])
    }

    /// A rejected response fails the load right away; the delegate still sees
    /// the response and the cancellation that follows it.
    @Test func delegateHearsAboutRejectedResponse() async {
        // Given
        let url = StubURLProtocol.register { $0.respond(statusCode: 500, chunks: [Data("error".utf8)]) }
        let loader = makeStubLoader()
        let delegate = EventLoggingDelegate()
        loader.delegate = delegate

        // When
        _ = loader.loadData(
            with: URLRequest(url: url),
            didReceiveData: { _, _ in delegate.log("loader: data") },
            completion: { _ in delegate.log("loader: completion") }
        )
        await delegate.didComplete.wait()
        await loader.drainDelegateQueue()

        // Then
        #expect(delegate.events == [
            "didCreateTask",
            "response 500",
            "loader: completion",
            "metrics",
            "complete \(URLError.Code.cancelled.rawValue)"
        ])
    }

    // MARK: Authentication

    @Test func delegateResolvesAuthenticationChallenge() async {
        // Given a server that requires credentials
        let resolution = OSAllocatedUnfairLock<ChallengeResolution?>(initialState: nil)
        let url = StubURLProtocol.registerChallenge { _, result in resolution.withLock { $0 = result } }
        let loader = makeStubLoader()
        loader.delegate = ChallengeDelegate(
            disposition: .useCredential,
            credential: URLCredential(user: "nuke", password: "secret", persistence: .none)
        )

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then the credential reaches the server
        #expect(resolution.withLock { $0 } == .useCredential(user: "nuke"))
        #expect(recorder.error == nil)
        #expect(recorder.body == Data("authorized".utf8))
    }

    @Test func delegateCancelsAuthenticationChallenge() async {
        // Given
        let url = StubURLProtocol.registerChallenge { _, _ in }
        let loader = makeStubLoader()
        loader.delegate = ChallengeDelegate(disposition: .cancelAuthenticationChallenge, credential: nil)

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect((recorder.error as? URLError)?.code == .cancelled)
        #expect(recorder.chunks.isEmpty)
    }

    /// Without a delegate that implements the task-level challenge method,
    /// the loader asks the system to handle the challenge.
    @Test(arguments: [false, true])
    func authenticationChallengeGetsDefaultHandling(hasDelegate: Bool) async {
        // Given
        let resolution = OSAllocatedUnfairLock<ChallengeResolution?>(initialState: nil)
        let url = StubURLProtocol.registerChallenge { _, result in resolution.withLock { $0 = result } }
        let loader = makeStubLoader()
        if hasDelegate {
            loader.delegate = EmptyDelegate()
        }

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(resolution.withLock { $0 } == .performDefaultHandling)
        #expect(recorder.error == nil)
        #expect(recorder.body == Data("authorized".utf8))
    }

    // MARK: Authentication Routing
    //
    // `DataLoader` implements only the task-level challenge method, so
    // `URLSession` sends it the session-wide challenges too, and it routes
    // them the way `URLSession` would.

    @Test func sessionLevelChallengeIsForwardedToDelegate() async {
        // Given a delegate that implements only the session-level method
        let url = StubURLProtocol.registerChallenge(authenticationMethod: NSURLAuthenticationMethodServerTrust) { _, _ in }
        let loader = makeStubLoader()
        let delegate = SessionLevelChallengeDelegate()
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then the delegate rejects the server trust challenge
        #expect(delegate.challengeCount == 1)
        #expect((recorder.error as? URLError)?.code == .cancelled)
    }

    @Test func taskLevelChallengeIsForwardedToDelegate() async {
        // Given a delegate that implements the task-level method
        let url = StubURLProtocol.registerChallenge(authenticationMethod: NSURLAuthenticationMethodServerTrust) { _, _ in }
        let loader = makeStubLoader()
        let delegate = TaskLevelChallengeDelegate()
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(delegate.challengeCount == 1)
        #expect((recorder.error as? URLError)?.code == .cancelled)
    }

    @Test func sessionWideChallengeGoesToSessionLevelMethodFirst() async {
        // Given a delegate that implements both methods
        let url = StubURLProtocol.registerChallenge(authenticationMethod: NSURLAuthenticationMethodServerTrust) { _, _ in }
        let loader = makeStubLoader()
        let delegate = BothLevelsChallengeDelegate()
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then server trust goes to the session-level method, as with `URLSession`
        #expect(delegate.sessionLevelCount == 1)
        #expect(delegate.taskLevelCount == 0)
        #expect((recorder.error as? URLError)?.code == .cancelled)
    }

    @Test func taskSpecificChallengeGoesToTaskLevelMethod() async {
        // Given a delegate that implements both methods
        let url = StubURLProtocol.registerChallenge { _, _ in }
        let loader = makeStubLoader()
        let delegate = BothLevelsChallengeDelegate()
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then HTTP Basic never goes to the session-level method
        #expect(delegate.sessionLevelCount == 0)
        #expect(delegate.taskLevelCount == 1)
        #expect((recorder.error as? URLError)?.code == .cancelled)
    }

    @Test func taskSpecificChallengeIsNotForwardedToSessionLevelMethod() async {
        // Given a delegate that implements only the session-level method
        let url = StubURLProtocol.registerChallenge { _, _ in }
        let loader = makeStubLoader()
        let delegate = SessionLevelChallengeDelegate()
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then the challenge gets default handling
        #expect(delegate.challengeCount == 0)
        #expect(recorder.error == nil)
    }

    // MARK: Redirects

    @Test func delegateCanRewriteRedirect() async throws {
        // Given
        let destination = StubURLProtocol.register { $0.respond(chunks: [Data("destination".utf8)]) }
        let rewritten = StubURLProtocol.register { $0.respond(chunks: [Data("rewritten".utf8)]) }
        let source = StubURLProtocol.registerRedirect(to: destination)
        let loader = makeStubLoader()
        loader.delegate = RedirectDelegate(target: rewritten)

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: source))

        // Then
        #expect(recorder.error == nil)
        #expect(recorder.body == Data("rewritten".utf8))
        #expect(recorder.responses.first?.url == rewritten)
    }

    /// Without a delegate that handles redirects, the loader follows them and
    /// delivers the destination's response.
    @Test(arguments: [false, true])
    func redirectIsFollowedWhenDelegateDoesNotHandleIt(hasDelegate: Bool) async throws {
        // Given
        let destination = StubURLProtocol.register { $0.respond(chunks: [Data("destination".utf8)]) }
        let source = StubURLProtocol.registerRedirect(to: destination)
        let loader = makeStubLoader()
        if hasDelegate {
            loader.delegate = EmptyDelegate()
        }

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: source))

        // Then
        #expect(recorder.error == nil)
        #expect(recorder.body == Data("destination".utf8))
        let response = try #require(recorder.responses.first as? HTTPURLResponse)
        #expect(response.url == destination)
        #expect(response.statusCode == 200)
    }

    // MARK: Session Decisions
    //
    // `URLSession` only asks about delayed requests in background sessions and
    // only reports waiting for connectivity when the network is down, so these
    // call the session delegate directly, on the queue `URLSession` uses.

    @Test func delayedRequestContinuesLoadingWithoutDelegate() async throws {
        // Given
        let loader = makeStubLoader()
        let request = URLRequest(url: Test.url)

        // When
        let decision = try #require(await loader.willBeginDelayedRequest(request))

        // Then
        #expect(decision.disposition == .continueLoading)
        #expect(decision.newRequest == nil)
    }

    @Test func delayedRequestDecisionComesFromDelegate() async throws {
        // Given
        let loader = makeStubLoader()
        var replacement = URLRequest(url: Test.url)
        replacement.setValue("1", forHTTPHeaderField: "X-Delayed")
        loader.delegate = DelayedRequestDelegate(replacement: replacement)

        // When
        let decision = try #require(await loader.willBeginDelayedRequest(URLRequest(url: Test.url)))

        // Then
        #expect(decision.disposition == .useNewRequest)
        #expect(decision.newRequest?.value(forHTTPHeaderField: "X-Delayed") == "1")
    }

    @Test func waitingForConnectivityIsForwarded() async {
        // Given
        let loader = makeStubLoader()
        let delegate = EventLoggingDelegate()
        loader.delegate = delegate

        // When
        await loader.onDelegateQueue { session, sessionDelegate in
            let task = session.dataTask(with: Test.url)
            (sessionDelegate as? URLSessionTaskDelegate)?.urlSession?(session, taskIsWaitingForConnectivity: task)
        }

        // Then
        #expect(delegate.events.contains("waitingForConnectivity"))
    }

    @Test func proposedResponseIsCachedWithoutDelegate() async throws {
        // Given
        let loader = makeStubLoader()
        let proposed = makeCachedResponse()

        // When
        let cached = try #require(await loader.willCacheResponse(proposed))

        // Then
        #expect(cached === proposed)
    }

    @Test func delegateCanPreventCaching() async throws {
        // Given
        let loader = makeStubLoader()
        loader.delegate = CachePolicyDelegate(allowsCaching: false)

        // When
        let cached = try #require(await loader.willCacheResponse(makeCachedResponse()))

        // Then
        #expect(cached == nil)
    }

    // MARK: Retention

    /// The documentation promises that the delegate is retained.
    @Test func delegateIsRetainedUntilReplaced() {
        // Given
        let loader = makeStubLoader()
        weak var weakDelegate: EmptyDelegate?
        do {
            let delegate = EmptyDelegate()
            weakDelegate = delegate
            loader.delegate = delegate
        }

        // Then
        #expect(weakDelegate != nil)

        // When
        loader.delegate = nil

        // Then
        #expect(weakDelegate == nil)
    }

    @Test func replacedDelegateStopsReceivingEvents() async {
        // Given
        let url = StubURLProtocol.register { $0.respond(chunks: [Data("x".utf8)]) }
        let loader = makeStubLoader()
        let first = EventLoggingDelegate()
        let second = EventLoggingDelegate()

        // When
        loader.delegate = first
        await LoadRecorder().loadToCompletion(with: loader, request: URLRequest(url: url))
        await loader.drainDelegateQueue()
        loader.delegate = second
        await LoadRecorder().loadToCompletion(with: loader, request: URLRequest(url: url))
        await loader.drainDelegateQueue()

        // Then each delegate hears about one load only
        #expect(first.events.filter { $0 == "complete" }.count == 1)
        #expect(second.events.filter { $0 == "complete" }.count == 1)
    }

    /// The loader reads `delegate` in every session callback and when each
    /// task is created, which happens on the thread that starts the request,
    /// so replacing it from another thread has to be synchronized – otherwise
    /// the process crashes or the thread sanitizer aborts the test run.
    @Test func delegateIsReplacedWhileLoadingData() async {
        // Given
        let loader = makeStubLoader()
        let urls = (0..<50).map { _ in
            StubURLProtocol.register { $0.respond(chunks: [Data("x".utf8)]) }
        }

        let writer = Task.detached {
            while !Task.isCancelled {
                loader.delegate = EventLoggingDelegate()
                await Task.yield()
            }
        }

        // When loading data while the delegate is being replaced
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    let recorder = LoadRecorder()
                    await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))
                    #expect(recorder.error == nil)
                    #expect(recorder.body == Data("x".utf8))
                }
            }
        }

        // Then no data races are reported
        writer.cancel()
        await writer.value
        #expect(loader.delegate is EventLoggingDelegate)
    }
}

// MARK: - Helpers

private func makeStubLoader(
    validate: @Sendable @escaping (URLResponse) -> Error? = DataLoader.validate
) -> DataLoader {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return DataLoader(configuration: configuration, validate: validate)
}

private func makeCachedResponse() -> CachedURLResponse {
    let response = HTTPURLResponse(url: Test.url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
    return CachedURLResponse(response: response, data: Data("cached".utf8))
}

extension DataLoader {
    /// Waits until the session's delegate queue runs everything enqueued so far.
    fileprivate func drainDelegateQueue() async {
        await withCheckedContinuation { continuation in
            session.delegateQueue.addBarrierBlock {
                continuation.resume()
            }
        }
    }

    /// Calls `body` with the session delegate on the queue that `URLSession`
    /// calls it on.
    fileprivate func onDelegateQueue(_ body: @escaping @Sendable (URLSession, URLSessionDelegate?) -> Void) async {
        await withCheckedContinuation { continuation in
            session.delegateQueue.addOperation {
                body(self.session, self.session.delegate)
                continuation.resume()
            }
        }
    }

    /// Returns `nil` if the session delegate doesn't implement the method.
    fileprivate func willBeginDelayedRequest(_ request: URLRequest) async -> (disposition: URLSession.DelayedRequestDisposition, newRequest: URLRequest?)? {
        await withCheckedContinuation { continuation in
            session.delegateQueue.addOperation {
                let task = self.session.dataTask(with: request)
                let delegate = self.session.delegate as? URLSessionTaskDelegate
                let isImplemented = delegate?.urlSession?(self.session, task: task, willBeginDelayedRequest: request) {
                    continuation.resume(returning: ($0, $1))
                } != nil
                if !isImplemented {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Returns `.none` if the session delegate doesn't implement the method.
    fileprivate func willCacheResponse(_ proposed: CachedURLResponse) async -> CachedURLResponse?? {
        await withCheckedContinuation { continuation in
            session.delegateQueue.addOperation {
                let task = self.session.dataTask(with: Test.url)
                let delegate = self.session.delegate as? URLSessionDataDelegate
                let isImplemented = delegate?.urlSession?(self.session, dataTask: task, willCacheResponse: proposed) {
                    continuation.resume(returning: .some($0))
                } != nil
                if !isImplemented {
                    continuation.resume(returning: .none)
                }
            }
        }
    }
}

/// Records the callbacks of a single ``DataLoader`` load.
private final class LoadRecorder: @unchecked Sendable {
    let completed = TestExpectation()
    let receivedData = TestExpectation()

    private struct State {
        var chunks: [Data] = []
        var responses: [URLResponse] = []
        var errors: [(any Error)?] = []
    }

    // `any Error` is not `Sendable`, so the state cannot be checked statically.
    private let state = OSAllocatedUnfairLock<State>(uncheckedState: State())

    var chunks: [Data] { state.withLockUnchecked { $0.chunks } }
    var body: Data { chunks.reduce(Data(), +) }
    var responses: [URLResponse] { state.withLockUnchecked { $0.responses } }
    var completionCount: Int { state.withLockUnchecked { $0.errors.count } }
    var error: (any Error)? { state.withLockUnchecked { $0.errors.first ?? nil } }

    func load(with loader: DataLoader, request: URLRequest) -> any Cancellable {
        loader.loadData(
            with: request,
            didReceiveData: { data, response in
                self.state.withLockUnchecked {
                    $0.chunks.append(data)
                    $0.responses.append(response)
                }
                self.receivedData.fulfill()
            },
            completion: { error in
                self.state.withLockUnchecked { $0.errors.append(error) }
                self.completed.fulfill()
            }
        )
    }

    func loadToCompletion(with loader: DataLoader, request: URLRequest) async {
        _ = load(with: loader, request: request)
        await completed.wait()
    }
}

// MARK: - Delegates

/// Logs the session events in the order the delegate hears about them.
private final class EventLoggingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let didComplete = TestExpectation()

    private let _events = OSAllocatedUnfairLock<[String]>(initialState: [])

    var events: [String] { _events.withLock { $0 } }

    func log(_ event: String) {
        _events.withLock { $0.append(event) }
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        log("didCreateTask")
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        log("response \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        log("data")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        log("metrics")
    }

    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        log("waitingForConnectivity")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error = error as? URLError {
            log("complete \(error.code.rawValue)")
        } else {
            log(error == nil ? "complete" : "complete \(String(describing: error))")
        }
        didComplete.fulfill()
    }
}

/// Implements none of the delegate methods.
private final class EmptyDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {}

private final class ChallengeDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let disposition: URLSession.AuthChallengeDisposition
    let credential: URLCredential?

    init(disposition: URLSession.AuthChallengeDisposition, credential: URLCredential?) {
        self.disposition = disposition
        self.credential = credential
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @Sendable @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(disposition, credential)
    }
}

/// Implements only the session-level challenge method and rejects the challenge.
private final class SessionLevelChallengeDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    var challengeCount: Int { _challengeCount.withLock { $0 } }
    private let _challengeCount = OSAllocatedUnfairLock(initialState: 0)

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        _challengeCount.withLock { $0 += 1 }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

/// Implements only the task-level challenge method and rejects the challenge.
private final class TaskLevelChallengeDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var challengeCount: Int { _challengeCount.withLock { $0 } }
    private let _challengeCount = OSAllocatedUnfairLock(initialState: 0)

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        _challengeCount.withLock { $0 += 1 }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

/// Implements both challenge methods and rejects the challenge.
private final class BothLevelsChallengeDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var sessionLevelCount: Int { _sessionLevelCount.withLock { $0 } }
    var taskLevelCount: Int { _taskLevelCount.withLock { $0 } }
    private let _sessionLevelCount = OSAllocatedUnfairLock(initialState: 0)
    private let _taskLevelCount = OSAllocatedUnfairLock(initialState: 0)

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        _sessionLevelCount.withLock { $0 += 1 }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        _taskLevelCount.withLock { $0 += 1 }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let target: URL

    init(target: URL) {
        self.target = target
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @Sendable @escaping (URLRequest?) -> Void) {
        completionHandler(URLRequest(url: target))
    }
}

private final class DelayedRequestDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let replacement: URLRequest

    init(replacement: URLRequest) {
        self.replacement = replacement
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willBeginDelayedRequest request: URLRequest, completionHandler: @Sendable @escaping (URLSession.DelayedRequestDisposition, URLRequest?) -> Void) {
        completionHandler(.useNewRequest, replacement)
    }
}

private final class CachePolicyDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let allowsCaching: Bool

    init(allowsCaching: Bool) {
        self.allowsCaching = allowsCaching
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse, completionHandler: @Sendable @escaping (CachedURLResponse?) -> Void) {
        completionHandler(allowsCaching ? proposedResponse : nil)
    }
}
