// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineResumableDataTests {
    private let dataLoader: _MockResumableDataLoader
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = _MockResumableDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    @Test func thatProgressIsReported() async throws {
        // Given an initial request failed mid download

        // Expect the progress for the first part of the download to be reported.
        var initialProgress: [ImageTask.Progress] = []
        do {
            let task = pipeline.imageTask(with: Test.request)
            for await progress in task.progress {
                initialProgress.append(progress)
            }
            _ = try await task.response
        } catch {
            // Expected failure
        }

        #expect(initialProgress == [
            ImageTask.Progress(completed: 3799, total: 22789),
            ImageTask.Progress(completed: 7598, total: 22789),
            ImageTask.Progress(completed: 11397, total: 22789)
        ])

        // Expect progress closure to continue reporting the progress of the
        // entire download
        var remainingProgress: [ImageTask.Progress] = []
        let task2 = pipeline.imageTask(with: Test.request)
        for await progress in task2.progress {
            remainingProgress.append(progress)
        }
        _ = try await task2.response

        #expect(remainingProgress == [
            ImageTask.Progress(completed: 15196, total: 22789),
            ImageTask.Progress(completed: 18995, total: 22789),
            ImageTask.Progress(completed: 22789, total: 22789)
        ])
    }

    /// A "206 Partial Content" without "Content-Length" has an unknown length,
    /// which is reported as unknown, the way it is for a download that was
    /// never resumed: adding the resumed bytes to `-1` would put the total
    /// below the bytes already received.
    @Test func progressOfAResumedDownloadWithUnknownLengthIsNotComplete() async throws {
        // GIVEN a download that failed after 10000 bytes
        let pipeline = ImagePipeline {
            $0.dataLoader = _MockChunkedRangeDataLoader()
            $0.imageCache = nil
        }
        _ = try? await pipeline.data(for: Test.request)

        // WHEN it is resumed by a response without "Content-Length"
        var progress: [ImageTask.Progress] = []
        let task = pipeline.imageTask(with: Test.request)
        for await value in task.progress {
            progress.append(value)
        }
        let response = try await task.response
        #expect((response.urlResponse as? HTTPURLResponse)?.statusCode == 206)

        // THEN the total is unknown, and the download is never reported as
        // complete before it is
        #expect(progress.count > 1)
        #expect(progress.last?.completed == 22789)
        for value in progress {
            #expect(value.total == -1, "\(value)")
            #expect(value.fraction == 0, "\(value)")
        }
    }

    @Test func resumedBytesAreReportedInTheMetrics() async throws {
        // GIVEN a pipeline that records diagnostics and a download that failed
        // mid-way
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDiagnosticsEnabled = true
        }
        let task1 = pipeline.imageTask(with: Test.request)
        _ = try? await task1.response
        let metrics1 = try #require(task1.metrics)
        #expect(metrics1.outcome == .failure)
        #expect(metrics1.bytes?.downloaded == 11397)
        #expect(metrics1.bytes?.expected == 22789)
        let failed = try #require(metrics1.jobs.last?.stages.first { $0.kind == .download })
        #expect(failed.resumedBytes == 0)

        // WHEN the download is resumed
        let task2 = pipeline.imageTask(with: Test.request)
        _ = try await task2.response

        // THEN the resumed bytes are reported
        let metrics2 = try #require(task2.metrics)
        #expect(metrics2.bytes?.downloaded == 22789)
        #expect(metrics2.bytes?.resumed == 11397)
        #expect(metrics2.bytes?.expected == 22789)
        let resumed = try #require(metrics2.jobs.last?.stages.first { $0.kind == .download })
        #expect(resumed.statusCode == 206)
    }

    /// On a "206 Partial Content" response, `expectedContentLength` covers only
    /// the remaining bytes while the accumulated data already contains the
    /// resumed prefix. The guard that decides whether to give the decoder a
    /// chance to produce a preview used to compare the two directly, so it was
    /// never satisfied and the resumed download produced no previews at all.
    @Test func previewsAreDeliveredWhenTheDownloadIsResumed() async throws {
        // GIVEN a pipeline with progressive decoding enabled
        let dataLoader = _MockResumableProgressiveDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
        }

        // GIVEN an initial download that delivers one scan and then fails
        var initialPreviews: [ImageResponse] = []
        let initialTask = pipeline.imageTask(with: Test.request)
        for await preview in initialTask.previews {
            initialPreviews.append(preview)
        }
        await #expect(throws: ImagePipeline.Error.self) {
            try await initialTask.response
        }
        #expect(initialPreviews.count == 1)

        // WHEN the download is resumed with "206 Partial Content"
        var previews: [ImageResponse] = []
        let task = pipeline.imageTask(with: Test.request)
        for await preview in task.previews {
            previews.append(preview)
        }
        let response = try await task.response

        // THEN the remaining scans are still delivered as previews
        #expect(dataLoader.isResumed)
        #expect(previews.count == 1)
        #expect(previews.allSatisfy { $0.container.isPreview })

        // THEN the final image is produced
        #expect(!response.container.isPreview)
    }

    @Test func thatResumableDataIsntSavedIfCancelledWhenDownloadIsCompleted() async throws {
        // GIVEN an initial partial download that fails and stores resumable data
        _ = try? await pipeline.imageTask(with: Test.request).response

        // WHEN the download is resumed and completes successfully (all bytes delivered)
        _ = try await pipeline.imageTask(with: Test.request).response

        // THEN no resumable data remains in storage: the completed download doesn't
        // produce a partial entry (ResumableData init requires data.count < Content-Length).
        let stored = await ResumableDataStorage.shared.removeResumableData(
            for: ImageRequest(url: Test.url),
            pipeline: pipeline
        )
        #expect(stored == nil)
    }

    @Test func resumableDataIsKeptWhenCancelledBeforeServerResponds() async throws {
        // GIVEN a pipeline whose delegate can suspend right before data loading
        let delegate = _GatingDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        // GIVEN an initial partial download that stores resumable data
        _ = try? await pipeline.imageTask(with: Test.request).response

        // WHEN the next attempt is cancelled while `willLoadData` is suspended,
        // after the pipeline has already taken the data out of the storage
        let entered = AsyncGate(), proceed = AsyncGate()
        delegate.entered = entered
        delegate.proceed = proceed

        let task = pipeline.imageTask(with: Test.request)
        let response = Task { try await task.response }
        await entered.wait()
        task.cancel()
        await Task { @ImagePipelineActor in }.value
        proceed.open()
        _ = try? await response.value
        await Task { @ImagePipelineActor in }.value

        // THEN the resumable data is still there for the next attempt
        let stored = await ResumableDataStorage.shared.removeResumableData(
            for: ImageRequest(url: Test.url),
            pipeline: pipeline
        )
        #expect(stored != nil)
    }

    @Test func resumedDownloadThatFailsAgainKeepsResumableData() async throws {
        // GIVEN a server that fails the first attempt at 8000 bytes and the
        // resumed one at 20000 bytes – more than the 206 "Content-Length"
        let dataLoader = _MockFailingRangeDataLoader()
        dataLoader.steps = [.fail(atOffset: 8000), .fail(atOffset: 20000), .serve]
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        // WHEN the download fails, is resumed, and fails again
        _ = try? await pipeline.data(for: Test.request)
        _ = try? await pipeline.data(for: Test.request)
        #expect(dataLoader.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=8000-")

        // THEN the third attempt resumes from where the second one failed
        let (data, _) = try await pipeline.data(for: Test.request)
        #expect(data == Test.data)
        #expect(dataLoader.requests.count == 3)
        #expect(dataLoader.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=20000-")
    }

    /// `DataLoader` rejects a "416 Range Not Satisfiable" before the pipeline
    /// sees the response, which used to look like a request that ended before
    /// the server responded, so the rejected range was put back and sent
    /// again on every attempt.
    @Test func rangeRejectedByTheServerIsNotSentAgain() async throws {
        // GIVEN a real `DataLoader` talking to a server that serves the first
        // 10000 bytes and drops the connection, then rejects every range
        let url = URL(string: "range-rejecting://example.com/image.jpeg")!
        _RangeRejectingURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [_RangeRejectingURLProtocol.self]
        let pipeline = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: configuration)
            $0.imageCache = nil
        }

        // WHEN the download fails once the pipeline has the first 10000 bytes
        let first = pipeline.imageTask(with: ImageRequest(url: url))
        var progress = first.progress.makeAsyncIterator()
        _ = await progress.next()
        _RangeRejectingURLProtocol.dropConnection()
        _ = try? await first.response

        // WHEN it is resumed, and the server rejects the range
        _ = try? await pipeline.data(for: ImageRequest(url: url))

        // THEN the next attempt asks for the whole resource, and gets it
        let (data, _) = try await pipeline.data(for: ImageRequest(url: url))
        #expect(data == Test.data)
        #expect(_RangeRejectingURLProtocol.ranges == [nil, "bytes=10000-", nil])
    }
}

/// Serves `Test.data` to its scheme: the first attempt delivers 10000 bytes
/// and stalls until `dropConnection()`, and every ranged request is rejected
/// with "416 Range Not Satisfiable".
private final class _RangeRejectingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _ranges: [String?] = []
    nonisolated(unsafe) private static var _stalled: _RangeRejectingURLProtocol?

    /// The "Range" header of every request, in order.
    static var ranges: [String?] { lock.withLock { _ranges } }

    static func reset() {
        lock.withLock {
            _ranges = []
            _stalled = nil
        }
    }

    static func dropConnection() {
        let stalled = lock.withLock { _stalled.take() }
        if let stalled {
            stalled.client?.urlProtocol(stalled, didFailWithError: URLError(.networkConnectionLost))
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "range-rejecting"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let range = request.value(forHTTPHeaderField: "Range")
        let attempt = Self.lock.withLock { () -> Int in
            Self._ranges.append(range)
            return Self._ranges.count
        }
        let data = Test.data
        let url = request.url!
        if range != nil {
            let response = HTTPURLResponse(url: url, statusCode: 416, httpVersion: "HTTP/1.1", headerFields: ["Content-Range": "bytes */\(data.count)"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Length": "\(data.count)",
            "Accept-Ranges": "bytes",
            "ETag": "\"v1\""
        ])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if attempt == 1 {
            client?.urlProtocol(self, didLoad: data[0..<10000])
            Self.lock.withLock { Self._stalled = self }
        } else {
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// Fails the first request after 10000 bytes, and answers a matching "Range"
/// request with a "206 Partial Content" that has no "Content-Length", served
/// in 4 KB chunks.
private final class _MockChunkedRangeDataLoader: DataLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var attempt = 0

    func loadData(with request: URLRequest,
                  didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                  completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let attempt = lock.withLock { () -> Int in
            self.attempt += 1
            return self.attempt
        }
        let data = Test.data
        let headers = ["Accept-Ranges": "bytes", "ETag": "\"v1\""]
        if attempt == 1 {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers.merging(["Content-Length": "\(data.count)"]) { $1 })!
            didReceiveData(data[0..<10000], response)
            completion(URLError(.networkConnectionLost))
        } else if let range = request.value(forHTTPHeaderField: "Range"), let offset = Int(_groups(regex: "bytes=(\\d*)-", in: range)[0]) {
            let response = HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: headers.merging(["Content-Range": "bytes \(offset)-\(data.count - 1)/\(data.count)"]) { $1 })!
            precondition(response.expectedContentLength == -1)
            for chunk in _createChunks(for: data[offset...], size: 4096) {
                didReceiveData(chunk, response)
            }
            completion(nil)
        } else {
            completion(URLError(.badServerResponse))
        }
        return AnonymousCancellable {}
    }
}

private final class _GatingDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    var entered: AsyncGate?
    var proceed: AsyncGate?

    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        entered?.open()
        await proceed?.wait()
        return urlRequest
    }
}

/// Serves `Test.data`, honoring "Range", and fails each attempt at the given
/// offset of the whole resource.
private final class _MockFailingRangeDataLoader: DataLoading, @unchecked Sendable {
    enum Step {
        case fail(atOffset: Int)
        case serve
    }

    let data = Test.data
    private let lock = NSLock()
    private var _steps: [Step] = []
    private var _requests: [URLRequest] = []

    var steps: [Step] {
        get { lock.withLock { _steps } }
        set { lock.withLock { _steps = newValue } }
    }
    var requests: [URLRequest] { lock.withLock { _requests } }

    func loadData(with request: URLRequest,
                  didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                  completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let step = lock.withLock { () -> Step in
            _requests.append(request)
            return _steps.isEmpty ? .serve : _steps.removeFirst()
        }
        let offset = request.value(forHTTPHeaderField: "If-Range") == "v1"
            ? request.value(forHTTPHeaderField: "Range").flatMap { Int(_groups(regex: "bytes=(\\d*)-", in: $0)[0]) }
            : nil
        var headerFields = ["Accept-Ranges": "bytes", "ETag": "v1"]
        if let offset {
            // "Content-Length" of a partial response covers the remaining bytes only.
            headerFields["Content-Range"] = "bytes \(offset)-\(data.count - 1)/\(data.count)"
            headerFields["Content-Length"] = "\(data.count - offset)"
        } else {
            headerFields["Content-Length"] = "\(data.count)"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: offset == nil ? 200 : 206, httpVersion: "HTTP/1.1", headerFields: headerFields)!
        switch step {
        case .fail(let end):
            didReceiveData(data[(offset ?? 0)..<end], response)
            completion(URLError(.networkConnectionLost))
        case .serve:
            didReceiveData(data[(offset ?? 0)...], response)
            completion(nil)
        }
        return AnonymousCancellable {}
    }
}

/// Serves a progressive JPEG in three scans: the first attempt delivers the
/// first scan and fails, the resumed attempt delivers the rest with
/// "206 Partial Content".
private final class _MockResumableProgressiveDataLoader: DataLoading, @unchecked Sendable {
    let data = Test.data(name: "progressive", extension: "jpeg")
    let eTag = "img_01"

    /// `true` when the server accepted the "If-Range" header.
    private(set) var isResumed = false

    func loadData(with request: URLRequest,
                  didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                  completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let chunks = _createChunks(for: data, size: data.count / 3)

        func makeResponse(statusCode: Int, headerFields: [String: String]) -> HTTPURLResponse {
            var headerFields = headerFields
            headerFields["Accept-Ranges"] = "bytes"
            headerFields["ETag"] = eTag
            return HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headerFields)!
        }

        if let range = request.allHTTPHeaderFields?["Range"], request.allHTTPHeaderFields?["If-Range"] == eTag {
            isResumed = true

            // The client already has the first chunk – serve the remaining ones.
            let offset = Int(_groups(regex: "bytes=(\\d*)-", in: range)[0])!
            let remainingChunks = chunks.filter { $0.startIndex >= offset }
            let remainingCount = data.count - offset

            // "Content-Length" of a partial response covers the remaining bytes only.
            let response = makeResponse(statusCode: 206, headerFields: [
                "Content-Range": "bytes \(offset)-\(data.count - 1)/\(data.count)",
                "Content-Length": "\(remainingCount)"
            ])
            for chunk in remainingChunks {
                didReceiveData(chunk, response)
            }
            completion(nil)
        } else {
            // Serve the first chunk and fail mid-download.
            let response = makeResponse(statusCode: 200, headerFields: ["Content-Length": "\(data.count)"])
            didReceiveData(chunks[0], response)
            completion(URLError(.networkConnectionLost))
        }
        return AnonymousCancellable {}
    }
}

private class _MockResumableDataLoader: DataLoading, @unchecked Sendable {
    let data: Data = Test.data(name: "fixture", extension: "jpeg")
    let eTag: String = "img_01"

    func loadData(with request: URLRequest,
                  didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                  completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let headers = request.allHTTPHeaderFields
        let data = self.data
        let eTag = self.eTag

        func sendChunk(_ chunk: Data, of data: Data, statusCode: Int) -> (Data, URLResponse) {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.2",
                headerFields: [
                    "Accept-Ranges": "bytes",
                    "ETag": eTag,
                    "Content-Range": "bytes \(chunk.startIndex)-\(chunk.endIndex)/\(data.count)",
                    "Content-Length": "\(data.count)"
                ]
            )!
            return (chunk, response)
        }

        // Check if the client already has some resumable data available.
        if let range = headers?["Range"], let validator = headers?["If-Range"] {
            let offset = _groups(regex: "bytes=(\\d*)-", in: range)[0]
            guard validator == eTag else {
                completion(URLError(.cancelled))
                return AnonymousCancellable {}
            }
            let remainingData = data[Int(offset)!...]
            let chunks = Array(_createChunks(for: remainingData, size: data.count / 6 + 1))
            for chunk in chunks {
                let (chunkData, response) = sendChunk(chunk, of: remainingData, statusCode: 206)
                didReceiveData(chunkData, response)
            }
            completion(nil)
        } else {
            var chunks = Array(_createChunks(for: data, size: data.count / 6 + 1))
            chunks.removeLast(chunks.count / 2)
            for chunk in chunks {
                let (chunkData, response) = sendChunk(chunk, of: data, statusCode: 200)
                didReceiveData(chunkData, response)
            }
            completion(NSError(domain: NSURLErrorDomain, code: Foundation.URLError.networkConnectionLost.rawValue, userInfo: [:]))
        }
        return AnonymousCancellable {}
    }
}
