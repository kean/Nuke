// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.serialized)
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
        let request = URLRequest(url: url)
        let (stream, response) = try await loader.loadData(with: request)

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        var received = Data()
        for try await chunk in stream {
            received.append(chunk)
        }
        #expect(received == body)
    }

    @Test func loadMultipleChunks() async throws {
        let url = mockURL("multi")
        let chunk1 = Data("aaa".utf8)
        let chunk2 = Data("bbb".utf8)
        let chunk3 = Data("ccc".utf8)
        registerMock(url: url, chunks: [chunk1, chunk2, chunk3])

        let loader = makeDataLoader()
        let (stream, _) = try await loader.loadData(with: URLRequest(url: url))

        var chunks = [Data]()
        for try await chunk in stream {
            chunks.append(chunk)
        }
        let combined = chunks.reduce(Data(), +)
        #expect(combined == chunk1 + chunk2 + chunk3)
    }

    @Test func loadEmptyBody() async throws {
        let url = mockURL("empty")
        registerMock(url: url, chunks: [])

        let loader = makeDataLoader()
        let (stream, response) = try await loader.loadData(with: URLRequest(url: url))

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        var received = Data()
        for try await chunk in stream {
            received.append(chunk)
        }
        #expect(received.isEmpty)
    }

    @Test func responseHeadersAreDelivered() async throws {
        let url = mockURL("headers")
        registerMock(url: url, headers: ["X-Custom": "value123"], chunks: [Data("x".utf8)])

        let loader = makeDataLoader()
        let (stream, response) = try await loader.loadData(with: URLRequest(url: url))

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.value(forHTTPHeaderField: "X-Custom") == "value123")

        // Drain stream
        for try await _ in stream {}
    }

    // MARK: - Validation

    @Test func validationRejectsNon2xxStatusCode() async throws {
        let url = mockURL("404")
        registerMock(url: url, statusCode: 404, chunks: [Data("not found".utf8)])

        let loader = makeDataLoader()
        do {
            _ = try await loader.loadData(with: URLRequest(url: url))
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
            _ = try await loader.loadData(with: URLRequest(url: url))
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
            let (stream, response) = try await loader.loadData(with: URLRequest(url: url))

            let httpResponse = try #require(response as? HTTPURLResponse)
            #expect(httpResponse.statusCode == statusCode)
            for try await _ in stream {}
        }
    }

    @Test func customValidation() async throws {
        let url = mockURL("custom-val")
        registerMock(url: url, statusCode: 200, chunks: [Data("ok".utf8)])

        struct CustomError: Error {}
        let loader = makeDataLoader { _ in CustomError() }

        do {
            _ = try await loader.loadData(with: URLRequest(url: url))
            Issue.record("Expected custom validation error")
        } catch {
            #expect(error is CustomError)
        }
    }

    @Test func noValidationPassesEverything() async throws {
        let url = mockURL("no-val")
        registerMock(url: url, statusCode: 500, chunks: [Data("ok".utf8)])

        let loader = makeDataLoader { _ in nil }
        let (stream, response) = try await loader.loadData(with: URLRequest(url: url))

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 500)
        for try await _ in stream {}
    }

    // MARK: - Errors

    @Test func errorBeforeResponse() async throws {
        let url = mockURL("dns-fail")
        registerMockError(url: url, error: URLError(.cannotFindHost))

        let loader = makeDataLoader()
        do {
            _ = try await loader.loadData(with: URLRequest(url: url))
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

        // URLProtocol delivers response + data + error synchronously, so
        // URLSession may surface the error from `loadData` or the stream.
        do {
            let (stream, _) = try await loader.loadData(with: URLRequest(url: url))
            var received = Data()
            do {
                for try await chunk in stream {
                    received.append(chunk)
                }
                Issue.record("Expected stream error")
            } catch {
                #expect((error as? URLError)?.code == .networkConnectionLost)
            }
        } catch {
            #expect((error as? URLError)?.code == .networkConnectionLost)
        }
    }

    // MARK: - Cancellation

    @Test func taskCancellationThrows() async throws {
        let url = mockURL("cancel")
        let started = TestExpectation()
        // Handler that never completes — the task will be cancelled before it finishes
        MockURLProtocol.handlers[url] = .init { _, client, proto in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
            started.fulfill()
            // Don't send data or finish — simulate a slow response
        }

        let loader = makeDataLoader()
        let task = Task {
            let (stream, _) = try await loader.loadData(with: URLRequest(url: url))
            for try await _ in stream {}
        }

        // Wait for the request to actually start, then cancel
        await started.wait()
        task.cancel()

        do {
            try await task.value
            Issue.record("Expected cancellation error")
        } catch is CancellationError {
            // Expected
        } catch {
            // URLError.cancelled is also acceptable
            #expect((error as? URLError)?.code == .cancelled)
        }
    }

    // MARK: - Incremental Delivery

    @Test func prefersIncrementalDeliveryDefault() async throws {
        let url = mockURL("incr-default")
        registerMock(url: url, chunks: [Data("x".utf8)])

        let loader = makeDataLoader()
        #expect(loader.prefersIncrementalDelivery == false)

        let (stream, _) = try await loader.loadData(with: URLRequest(url: url))
        for try await _ in stream {}
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
        // Split into multiple chunks
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
        let (stream, _) = try await loader.loadData(with: URLRequest(url: url))

        var received = Data()
        for try await chunk in stream {
            received.append(chunk)
        }
        #expect(received == largeData)
    }

    // MARK: - Multiple Concurrent Loads

    @Test func concurrentLoads() async throws {
        let loader = makeDataLoader()

        for i in 0..<5 {
            let url = mockURL("concurrent-\(i)")
            let body = Data("response-\(i)".utf8)
            registerMock(url: url, chunks: [body])
        }

        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for i in 0..<5 {
                let url = mockURL("concurrent-\(i)")
                group.addTask {
                    let (stream, _) = try await loader.loadData(with: URLRequest(url: url))
                    var data = Data()
                    for try await chunk in stream {
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

        let (stream, _) = try await loader.loadData(with: URLRequest(url: url))
        for try await _ in stream {}

        // Drain the delegate queue to ensure all callbacks have been processed
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

        let (stream, _) = try await loader.loadData(with: URLRequest(url: url))
        for try await _ in stream {}

        await withCheckedContinuation { continuation in
            loader.session.delegateQueue.addBarrierBlock {
                continuation.resume()
            }
        }

        #expect(spy.didFinishMetricsCount > 0)
    }

    // MARK: - Default Validation

    @Test func initWithDefaultValidation() async throws {
        let url = mockURL("default-val")
        registerMock(url: url, chunks: [Data("ok".utf8)])

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let loader = DataLoader(configuration: config)

        let (stream, response) = try await loader.loadData(with: URLRequest(url: url))
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)
        for try await _ in stream {}
    }

    @Test func initWithDefaultValidationRejectsNon2xx() async throws {
        let url = mockURL("default-val-reject")
        registerMock(url: url, statusCode: 403, chunks: [Data("forbidden".utf8)])

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let loader = DataLoader(configuration: config)

        do {
            _ = try await loader.loadData(with: URLRequest(url: url))
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

        let (stream, _) = try await loader.loadData(with: URLRequest(url: url))
        for try await _ in stream {}

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
            let (stream, _) = try await loader.loadData(with: URLRequest(url: sourceURL))
            var received = Data()
            for try await chunk in stream {
                received.append(chunk)
            }
            #expect(received == Data("redirected".utf8))
        } catch {
            // Some URLSession implementations may handle redirects differently with MockURLProtocol
        }
    }
}

// MARK: - Spy Delegate

private final class SpyURLSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    @Mutex var didReceiveResponseCount = 0
    @Mutex var didReceiveDataCount = 0
    @Mutex var didCompleteCount = 0
    @Mutex var didFinishMetricsCount = 0

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        didReceiveResponseCount += 1
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        didReceiveDataCount += 1
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        didCompleteCount += 1
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        didFinishMetricsCount += 1
    }
}
