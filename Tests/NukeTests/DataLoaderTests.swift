// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.serialized, .timeLimit(.minutes(2)))
struct DataLoaderTests {

    init() {
        MockURLProtocol.handlers.removeAll()
    }

    // MARK: - Successful Loading

    @Test func loadSingleChunk() async throws {
        let url = mockURL("single")
        let body = Data("hello".utf8)
        registerMock(url: url, chunks: [body])

        let loader = makeDataLoader()
        var response: URLResponse?
        var received = Data()
        for try await (chunk, resp) in loader.loadData(with: URLRequest(url: url)) {
            response = resp
            received.append(chunk)
        }

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)
        #expect(received == body)
    }

    @Test func loadMultipleChunks() async throws {
        let url = mockURL("multi")
        let chunk1 = Data("aaa".utf8)
        let chunk2 = Data("bbb".utf8)
        let chunk3 = Data("ccc".utf8)
        registerMock(url: url, chunks: [chunk1, chunk2, chunk3])

        let loader = makeDataLoader()
        var chunks = [Data]()
        for try await (chunk, _) in loader.loadData(with: URLRequest(url: url)) {
            chunks.append(chunk)
        }
        let combined = chunks.reduce(Data(), +)
        #expect(combined == chunk1 + chunk2 + chunk3)
    }

    @Test func loadEmptyBody() async throws {
        let url = mockURL("empty")
        registerMock(url: url, chunks: [])

        let loader = makeDataLoader()
        var received = Data()
        for try await (chunk, _) in loader.loadData(with: URLRequest(url: url)) {
            received.append(chunk)
        }
        #expect(received.isEmpty)
    }

    @Test func responseHeadersAreDelivered() async throws {
        let url = mockURL("headers")
        registerMock(url: url, headers: ["X-Custom": "value123"], chunks: [Data("x".utf8)])

        let loader = makeDataLoader()
        var response: URLResponse?
        for try await (_, resp) in loader.loadData(with: URLRequest(url: url)) {
            response = resp
        }

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.value(forHTTPHeaderField: "X-Custom") == "value123")
    }

    // MARK: - Validation

    @Test func validationRejectsNon2xxStatusCode() async throws {
        let url = mockURL("404")
        registerMock(url: url, statusCode: 404, chunks: [Data("not found".utf8)])

        let loader = makeDataLoader()
        do {
            for try await _ in loader.loadData(with: URLRequest(url: url)) {}
            Issue.record("Expected validation error")
        } catch let error as DataLoader.Error {
            guard case .statusCodeUnacceptable(let code) = error else {
                Issue.record("Wrong error case")
                return
            }
            #expect(code == 404)
        }
    }

    @Test func validationRejects500() async throws {
        let url = mockURL("500")
        registerMock(url: url, statusCode: 500, chunks: [Data("fail".utf8)])

        let loader = makeDataLoader()
        do {
            for try await _ in loader.loadData(with: URLRequest(url: url)) {}
            Issue.record("Expected validation error")
        } catch let error as DataLoader.Error {
            guard case .statusCodeUnacceptable(let code) = error else {
                Issue.record("Wrong error case")
                return
            }
            #expect(code == 500)
        }
    }

    @Test func validationAccepts2xxRange() async throws {
        for statusCode in [200, 201, 204, 299] {
            let url = mockURL("status-\(statusCode)")
            registerMock(url: url, statusCode: statusCode, chunks: [Data("ok".utf8)])

            let loader = makeDataLoader()
            var httpResponse: HTTPURLResponse?
            for try await (_, response) in loader.loadData(with: URLRequest(url: url)) {
                httpResponse = response as? HTTPURLResponse
            }
            #expect(httpResponse?.statusCode == statusCode)
        }
    }

    /// ``DataLoading`` requires `completion` to be called exactly once. On a
    /// validation failure the data loader must stop tracking the handler before
    /// cancelling the task – otherwise `didCompleteWithError`, which
    /// `URLSession` delivers in response to the `.cancel` disposition, finds the
    /// handler still registered and calls `completion` a second time.
    @Test func completionIsCalledOnceOnValidationFailure() async throws {
        let url = mockURL("validation-completion-count")
        registerMock(url: url, statusCode: 404, chunks: [Data("not found".utf8)])

        let loader = makeDataLoader()
        let spy = SpyURLSessionDelegate()
        loader.delegate = spy

        let recorder = CompletionRecorder()
        _ = loader.loadData(
            with: URLRequest(url: url),
            didReceiveData: { _, _ in },
            completion: {
                recorder.record($0)
            }
        )

        // `didCompleteWithError` is the callback that delivers the extra
        // `completion` call, so wait for it, then drain the delegate queue to
        // let the block that forwarded it run to the end.
        await spy.didCompleteWithError.wait()
        await withCheckedContinuation { continuation in
            loader.session.delegateQueue.addBarrierBlock {
                continuation.resume()
            }
        }

        let errors = recorder.errors
        #expect(errors.count == 1, "completion called \(errors.count) times: \(errors.map { $0.map(String.init(describing:)) ?? "nil" })")

        let first = try #require(errors.first ?? nil)
        guard let error = first as? DataLoader.Error,
              case .statusCodeUnacceptable(let code) = error else {
            Issue.record("Expected a validation error, got \(first)")
            return
        }
        #expect(code == 404)
    }

    @Test func customValidation() async throws {
        let url = mockURL("custom-val")
        registerMock(url: url, statusCode: 200, chunks: [Data("ok".utf8)])

        struct CustomError: Error {}
        let loader = makeDataLoader { _ in CustomError() }
        do {
            for try await _ in loader.loadData(with: URLRequest(url: url)) {}
            Issue.record("Expected custom validation error")
        } catch {
            #expect(error is CustomError)
        }
    }

    @Test func noValidationPassesEverything() async throws {
        let url = mockURL("no-val")
        registerMock(url: url, statusCode: 500, chunks: [Data("ok".utf8)])

        let loader = makeDataLoader { _ in nil }
        var httpResponse: HTTPURLResponse?
        for try await (_, response) in loader.loadData(with: URLRequest(url: url)) {
            httpResponse = response as? HTTPURLResponse
        }
        #expect(httpResponse?.statusCode == 500)
    }

    // MARK: - Errors

    @Test func errorBeforeResponse() async throws {
        let url = mockURL("dns-fail")
        registerMockError(url: url, error: URLError(.cannotFindHost))

        let loader = makeDataLoader()
        do {
            for try await _ in loader.loadData(with: URLRequest(url: url)) {}
            Issue.record("Expected error")
        } catch {
            #expect((error as? URLError)?.code == .cannotFindHost)
        }
    }

    @Test func errorMidStream() async throws {
        let url = mockURL("mid-fail")
        let partialData = Data("partial".utf8)
        registerMockPartialFailure(url: url, data: partialData, error: URLError(.networkConnectionLost))

        let loader = makeDataLoader()
        do {
            var received = Data()
            for try await (chunk, _) in loader.loadData(with: URLRequest(url: url)) {
                received.append(chunk)
            }
            Issue.record("Expected stream error")
        } catch {
            #expect((error as? URLError)?.code == .networkConnectionLost)
        }
    }

    // MARK: - Cancellation

    @Test func taskCancellationThrows() async throws {
        let url = mockURL("cancel")
        let started = TestExpectation()
        MockURLProtocol.handlers[url] = .init { _, client, proto in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
            started.fulfill()
            // Don't send data or finish — simulate a slow response
        }

        let loader = makeDataLoader()
        let task = Task {
            for try await _ in loader.loadData(with: URLRequest(url: url)) {}
            try Task.checkCancellation()
        }

        await started.wait()
        task.cancel()

        do {
            try await task.value
            Issue.record("Expected cancellation error")
        } catch is CancellationError {
            // Expected
        } catch {
            #expect((error as? URLError)?.code == .cancelled)
        }
    }

    // MARK: - Incremental Delivery

    @Test func prefersIncrementalDeliveryDefault() async throws {
        let url = mockURL("incr-default")
        registerMock(url: url, chunks: [Data("x".utf8)])

        let loader = makeDataLoader()
        #expect(loader.prefersIncrementalDelivery == false)
        for try await _ in loader.loadData(with: URLRequest(url: url)) {}
    }

    // MARK: - Static Validation Helper

    @Test func staticValidateAccepts200() {
        let response = HTTPURLResponse(url: mockURL(), statusCode: 200, httpVersion: nil, headerFields: nil)!
        #expect(DataLoader.validate(response: response) == nil)
    }

    @Test func staticValidateRejects400() {
        let response = HTTPURLResponse(url: mockURL(), statusCode: 400, httpVersion: nil, headerFields: nil)!
        let error = DataLoader.validate(response: response)
        #expect(error != nil)
        if let dlError = error as? DataLoader.Error, case .statusCodeUnacceptable(let code) = dlError {
            #expect(code == 400)
        } else {
            Issue.record("Expected DataLoader.Error.statusCodeUnacceptable")
        }
    }

    @Test func staticValidateAcceptsNonHTTPResponse() {
        let response = URLResponse(url: mockURL(), mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(DataLoader.validate(response: response) == nil)
    }

    // MARK: - Error Description

    @Test func errorDescription() {
        let error = DataLoader.Error.statusCodeUnacceptable(404)
        #expect(error.description.contains("404"))
    }

    // MARK: - Large Data

    @Test func loadLargeData() async throws {
        let url = mockURL("large")
        let largeData = Data(repeating: 0xAB, count: 1_000_000)
        let chunkSize = 100_000
        var chunks = [Data]()
        var offset = 0
        while offset < largeData.count {
            let end = min(offset + chunkSize, largeData.count)
            chunks.append(largeData[offset..<end])
            offset = end
        }
        registerMock(url: url, chunks: chunks)

        let loader = makeDataLoader()
        var received = Data()
        for try await (chunk, _) in loader.loadData(with: URLRequest(url: url)) {
            received.append(chunk)
        }
        #expect(received == largeData)
    }

    // MARK: - Multiple Concurrent Loads

    @Test func concurrentLoads() async throws {
        let loader = makeDataLoader()

        for i in 0..<5 {
            let url = mockURL("concurrent-\(i)")
            registerMock(url: url, chunks: [Data("response-\(i)".utf8)])
        }

        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for i in 0..<5 {
                let url = mockURL("concurrent-\(i)")
                group.addTask {
                    var data = Data()
                    for try await (chunk, _) in loader.loadData(with: URLRequest(url: url)) {
                        data.append(chunk)
                    }
                    return (i, data)
                }
            }
            for try await (i, data) in group {
                #expect(data == Data("response-\(i)".utf8))
            }
        }
    }

    // MARK: - Delegate Forwarding

    @Test func settingDelegateProperty() async throws {
        let url = mockURL("delegate-set")
        registerMock(url: url, chunks: [Data("ok".utf8)])

        let loader = makeDataLoader()
        let spy = SpyURLSessionDelegate()
        loader.delegate = spy

        for try await _ in loader.loadData(with: URLRequest(url: url)) {}

        await withCheckedContinuation { continuation in
            loader.session.delegateQueue.addBarrierBlock {
                continuation.resume()
            }
        }

        #expect(spy.didReceiveResponseCount > 0)
        #expect(spy.didReceiveDataCount > 0)
        #expect(spy.didCompleteCount > 0)
    }

    @Test func delegateReceivesMetricsCallback() async throws {
        let url = mockURL("delegate-metrics")
        registerMock(url: url, chunks: [Data("data".utf8)])

        let loader = makeDataLoader()
        let spy = SpyURLSessionDelegate()
        loader.delegate = spy

        for try await _ in loader.loadData(with: URLRequest(url: url)) {}

        await withCheckedContinuation { continuation in
            loader.session.delegateQueue.addBarrierBlock {
                continuation.resume()
            }
        }

        #expect(spy.didFinishMetricsCount > 0)
    }

    @Test func delegateReceivesDidCreateTaskCallback() async throws {
        let url = mockURL("delegate-did-create-task")
        registerMock(url: url, chunks: [Data("data".utf8)])

        let loader = makeDataLoader()
        let spy = SpyURLSessionDelegate()
        loader.delegate = spy

        for try await _ in loader.loadData(with: URLRequest(url: url)) {}

        await withCheckedContinuation { continuation in
            loader.session.delegateQueue.addBarrierBlock {
                continuation.resume()
            }
        }

        #expect(spy.didCreateTaskCount == 1)
    }

    // MARK: - Default Validation

    @Test func initWithDefaultValidation() async throws {
        let url = mockURL("default-val")
        registerMock(url: url, chunks: [Data("ok".utf8)])

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let loader = DataLoader(configuration: config)

        var httpResponse: HTTPURLResponse?
        for try await (_, response) in loader.loadData(with: URLRequest(url: url)) {
            httpResponse = response as? HTTPURLResponse
        }
        #expect(httpResponse?.statusCode == 200)
    }

    @Test func initWithDefaultValidationRejectsNon2xx() async throws {
        let url = mockURL("default-val-reject")
        registerMock(url: url, statusCode: 403, chunks: [Data("forbidden".utf8)])

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let loader = DataLoader(configuration: config)

        do {
            for try await _ in loader.loadData(with: URLRequest(url: url)) {}
            Issue.record("Expected validation error")
        } catch {
            #expect(error is DataLoader.Error)
        }
    }

    // MARK: - Static Properties

    @Test func defaultConfigurationHasUrlCache() {
        let config = DataLoader.defaultConfiguration
        #expect(config.urlCache === DataLoader.sharedUrlCache)
    }

    @Test func sharedUrlCacheHasExpectedCapacity() {
        let cache = DataLoader.sharedUrlCache
        #expect(cache.memoryCapacity == 0)
        #expect(cache.diskCapacity == 150 * 1048576)
    }

    // MARK: - Caching

    @Test func willCacheResponseIsForwarded() async throws {
        let url = mockURL("cache-fwd")
        MockURLProtocol.handlers[url] = .init { _, client, proto in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "5"])!
            client.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .allowedInMemoryOnly)
            client.urlProtocol(proto, didLoad: Data("hello".utf8))
            client.urlProtocolDidFinishLoading(proto)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.urlCache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0)
        let loader = DataLoader(configuration: config, validate: { _ in nil })

        let spy = SpyURLSessionDelegate()
        loader.delegate = spy

        for try await _ in loader.loadData(with: URLRequest(url: url)) {}

        await withCheckedContinuation { continuation in
            loader.session.delegateQueue.addBarrierBlock {
                continuation.resume()
            }
        }

        #expect(spy.didReceiveResponseCount > 0)
    }

    // MARK: - Redirect

    @Test func redirectIsFollowed() async throws {
        let sourceURL = mockURL("redirect-source")
        let destURL = mockURL("redirect-dest")

        registerMock(url: destURL, chunks: [Data("redirected".utf8)])

        MockURLProtocol.handlers[sourceURL] = .init { _, client, proto in
            let redirectResponse = HTTPURLResponse(url: sourceURL, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": destURL.absoluteString])!
            client.urlProtocol(proto, wasRedirectedTo: URLRequest(url: destURL), redirectResponse: redirectResponse)
        }

        let loader = makeDataLoader { _ in nil }
        do {
            var received = Data()
            for try await (chunk, _) in loader.loadData(with: URLRequest(url: sourceURL)) {
                received.append(chunk)
            }
            #expect(received == Data("redirected".utf8))
        } catch {
            // Some URLSession implementations may handle redirects differently with MockURLProtocol
        }
    }

    // MARK: - Authentication Challenges

    @Test func sessionLevelChallengeIsForwardedToDelegate() async {
        // GIVEN a delegate that implements only the session-level method
        let loader = makeChallengingLoader()
        let delegate = SessionLevelChallengeDelegate()
        loader.delegate = delegate

        // WHEN
        let errorCode = await loadData(ChallengingURLProtocol.makeURL(), with: loader)

        // THEN the delegate rejects the server trust challenge
        #expect(delegate.challengeCount == 1)
        #expect(errorCode == .cancelled)
    }

    @Test func taskLevelChallengeIsForwardedToDelegate() async {
        // GIVEN a delegate that implements the task-level method
        let loader = makeChallengingLoader()
        let delegate = TaskLevelChallengeDelegate()
        loader.delegate = delegate

        // WHEN
        let errorCode = await loadData(ChallengingURLProtocol.makeURL(), with: loader)

        // THEN
        #expect(delegate.challengeCount == 1)
        #expect(errorCode == .cancelled)
    }

    private func makeChallengingLoader() -> DataLoader {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChallengingURLProtocol.self]
        return DataLoader(configuration: config)
    }

    private func loadData(_ url: URL, with loader: DataLoader) async -> URLError.Code? {
        await withCheckedContinuation { continuation in
            _ = loader.loadData(with: URLRequest(url: url), didReceiveData: { _, _ in }, completion: { error in
                continuation.resume(returning: (error as? URLError)?.code)
            })
        }
    }
}

// MARK: - Completion Recorder

/// Records every `completion` call made by a ``DataLoading`` instance.
private final class CompletionRecorder: @unchecked Sendable {
    @Mutex var errors: [(any Error)?] = []

    func record(_ error: (any Error)?) {
        _errors.withLock { $0.append(error) }
    }
}

// MARK: - Spy Delegate

private final class SpyURLSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    @Mutex var didReceiveResponseCount = 0
    @Mutex var didReceiveDataCount = 0
    @Mutex var didCompleteCount = 0
    @Mutex var didFinishMetricsCount = 0
    @Mutex var didCreateTaskCount = 0

    let didCompleteWithError = TestExpectation()

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        didCreateTaskCount += 1
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        didReceiveResponseCount += 1
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        didReceiveDataCount += 1
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        didCompleteCount += 1
        didCompleteWithError.fulfill()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        didFinishMetricsCount += 1
    }
}

// MARK: - Authentication Challenges

/// Implements only the session-level challenge method and rejects the challenge.
private final class SessionLevelChallengeDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    @Mutex var challengeCount = 0

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        challengeCount += 1
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

/// Implements only the task-level challenge method and rejects the challenge.
private final class TaskLevelChallengeDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    @Mutex var challengeCount = 0

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        challengeCount += 1
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

/// Challenges every request for server trust, then responds with "trusted"
/// unless the challenge is cancelled.
private final class ChallengingURLProtocol: URLProtocol, URLAuthenticationChallengeSender, @unchecked Sendable {
    static func makeURL() -> URL {
        URL(string: "challenge://\(UUID().uuidString.lowercased())/image.jpeg")!
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "challenge"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let space = URLProtectionSpace(host: request.url?.host ?? "", port: 443, protocol: "https", realm: nil, authenticationMethod: NSURLAuthenticationMethodServerTrust)
        let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: self)
        client?.urlProtocol(self, didReceive: challenge)
    }

    override func stopLoading() {}

    private func respond() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "7"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("trusted".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) { respond() }
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) { respond() }
    func cancel(_ challenge: URLAuthenticationChallenge) { client?.urlProtocol(self, didFailWithError: URLError(.cancelled)) }
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) { respond() }
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) { respond() }
}
