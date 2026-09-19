// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// Resumable downloads end-to-end: what the pipeline sends back to the server
/// on the next attempt, and what it does with the answer.
///
/// - seealso: ``ImagePipeline/Configuration-swift.struct/isResumableDataEnabled``
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineResumableDownloadTests {
    private let server: _RangeServer
    private let dataCache: MockDataCache
    private let pipeline: ImagePipeline

    init() {
        let server = _RangeServer(data: Test.data, validator: ["ETag": "\"v1\""])
        let dataCache = MockDataCache()
        self.server = server
        self.dataCache = dataCache
        self.pipeline = ImagePipeline {
            $0.dataLoader = server
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
    }

    // MARK: - Failure

    @Test func failedDownloadIsResumedWithTheETag() async throws {
        // GIVEN a download that failed after 10000 bytes
        server.steps = [.fail(after: 10000), .serve]
        await #expect(throws: ImagePipeline.Error.self) {
            try await pipeline.data(for: Test.request)
        }

        // WHEN
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN the server is asked for the rest of the bytes
        let request = try #require(server.requests.last)
        #expect(request.value(forHTTPHeaderField: "Range") == "bytes=10000-")
        #expect(request.value(forHTTPHeaderField: "If-Range") == "\"v1\"")

        // THEN the resumed bytes are stitched together with the rest
        #expect((response as? HTTPURLResponse)?.statusCode == 206)
        #expect(data == Test.data)
        #expect(dataCache.store[Test.url.absoluteString] == Test.data)
    }

    /// When the attempt that was supposed to resume the download fails before
    /// the server responds, the pipeline has already taken the bytes out of the
    /// storage – it has to put them back for the attempt after it.
    @Test func failureBeforeTheServerRespondsKeepsTheBytes() async throws {
        // GIVEN a download that failed after 10000 bytes, and a retry that
        // failed without a response
        server.steps = [.fail(after: 10000), .failBeforeResponse, .serve]
        _ = try? await pipeline.data(for: Test.request)
        await #expect(throws: ImagePipeline.Error.self) {
            try await pipeline.data(for: Test.request)
        }

        // WHEN
        let (data, _) = try await pipeline.data(for: Test.request)

        // THEN the third attempt still resumes where the first one left off
        #expect(server.requests.count == 3)
        #expect(server.requests.map { $0.value(forHTTPHeaderField: "Range") } == [nil, "bytes=10000-", "bytes=10000-"])
        #expect(data == Test.data)
    }

    /// The same goes for an attempt that `willLoadData` rejects: the bytes
    /// are taken out of the storage before the delegate is asked.
    @Test func delegateFailureKeepsTheBytes() async throws {
        // GIVEN a download that failed after 10000 bytes, and a retry that
        // the delegate rejected
        let delegate = _RecordingDelegate()
        delegate.failingAttempts = [2]
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = server
            $0.imageCache = nil
        }
        server.steps = [.fail(after: 10000), .serve]
        _ = try? await pipeline.data(for: Test.request)
        await #expect(throws: ImagePipeline.Error.self) {
            try await pipeline.data(for: Test.request)
        }

        // WHEN
        let (data, _) = try await pipeline.data(for: Test.request)

        // THEN
        #expect(server.requests.count == 2)
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=10000-")
        #expect(data == Test.data)
    }

    // MARK: - Cancellation

    /// The docs promise to resume after "either a failure or a cancellation".
    @Test func cancelledDownloadIsResumed() async throws {
        // GIVEN a download that stalls after 8000 bytes
        server.steps = [.stall(after: 8000), .serve]
        let task = pipeline.imageTask(with: Test.request)
        for await progress in task.progress {
            #expect(progress == ImageTask.Progress(completed: 8000, total: 22789))
            break
        }

        // WHEN it gets cancelled
        task.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
        #expect(server.cancelCount == 1)

        // THEN the next attempt picks up from where it was cancelled
        let (data, response) = try await pipeline.data(for: Test.request)
        let request = try #require(server.requests.last)
        #expect(request.value(forHTTPHeaderField: "Range") == "bytes=8000-")
        #expect((response as? HTTPURLResponse)?.statusCode == 206)
        #expect(data == Test.data)
    }

    // MARK: - Server Responses

    /// A server is free to ignore "Range" (or reject "If-Range") and send the
    /// whole resource with "200 OK" – the resumed bytes must not end up in
    /// front of it.
    @Test func serverIgnoringTheRangeRestartsTheDownload() async throws {
        // GIVEN
        server.steps = [.fail(after: 10000), .ignoreRange]
        _ = try? await pipeline.data(for: Test.request)

        // WHEN
        let progress = _ProgressRecorder()
        let task = pipeline.makeStartedImageTask(with: Test.request, isDataTask: true) { event, _ in
            if case .progress(let value) = event { progress.append(value) }
        }
        let response = try await task.response

        // THEN the data is the resource, not the resumed bytes followed by it
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=10000-")
        #expect(response.urlResponse.map { ($0 as? HTTPURLResponse)?.statusCode } == 200)
        #expect(response.container.data == Test.data)
        #expect(progress.values.last == ImageTask.Progress(completed: 22789, total: 22789))
        #expect(progress.values.allSatisfy { $0.total == 22789 })
    }

    /// "If-Range" is what keeps the bytes of the old version out of the new
    /// one: a server with a different version answers with all of it.
    @Test func resourceThatChangedIsDownloadedFromScratch() async throws {
        // GIVEN a download that failed after 10000 bytes
        server.steps = [.fail(after: 10000), .serve, .fail(after: 5000), .serve]
        _ = try? await pipeline.data(for: Test.request)

        // WHEN the resource changes before the next attempt
        let newData = Test.data(name: "fixture-tiny", extension: "jpeg")
        server.resource = (newData, ["ETag": "\"v2\""])
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN
        #expect(server.requests.last?.value(forHTTPHeaderField: "If-Range") == "\"v1\"")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == newData)

        // THEN the next interruption resumes with the new validator
        _ = try? await pipeline.data(for: ImageRequest(url: Test.url, options: [.disableDiskCacheReads]))
        let (resumed, _) = try await pipeline.data(for: ImageRequest(url: Test.url, options: [.disableDiskCacheReads]))
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=5000-")
        #expect(server.requests.last?.value(forHTTPHeaderField: "If-Range") == "\"v2\"")
        #expect(resumed == newData)
    }

    // MARK: - Configuration

    @Test func resumableDataIsNotUsedWhenDisabled() async throws {
        // GIVEN
        let pipeline = ImagePipeline {
            $0.dataLoader = server
            $0.imageCache = nil
            $0.isResumableDataEnabled = false
        }
        server.steps = [.fail(after: 10000), .serve]
        _ = try? await pipeline.data(for: Test.request)

        // WHEN
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == nil)
        #expect(server.requests.last?.value(forHTTPHeaderField: "If-Range") == nil)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == Test.data)
    }

    @Test func resumableDataBelongsToThePipelineThatDownloadedIt() async throws {
        // GIVEN a download that failed in one pipeline
        let otherPipeline = ImagePipeline {
            $0.dataLoader = server
            $0.imageCache = nil
        }
        server.steps = [.fail(after: 10000), .serve, .serve]
        _ = try? await pipeline.data(for: Test.request)

        // WHEN the other pipeline loads the same image
        _ = try await otherPipeline.data(for: Test.request)

        // THEN it starts from scratch and leaves the bytes where they are
        #expect(server.requests.count == 2)
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == nil)
        _ = try await pipeline.data(for: Test.request)
        #expect(server.requests.count == 3)
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=10000-")
    }

    // MARK: - Delegate

    /// The docs say that `willLoadData` is called "after resumable data headers
    /// are applied".
    @Test func willLoadDataSeesTheResumeHeaders() async throws {
        // GIVEN
        let delegate = _RecordingDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = server
            $0.imageCache = nil
        }
        server.steps = [.fail(after: 10000), .serve]
        _ = try? await pipeline.data(for: Test.request)

        // WHEN
        _ = try await pipeline.data(for: Test.request)

        // THEN
        let requests = delegate.requests
        #expect(requests.count == 2)
        #expect(requests.first?.value(forHTTPHeaderField: "Range") == nil)
        #expect(requests.last?.value(forHTTPHeaderField: "Range") == "bytes=10000-")
        #expect(requests.last?.value(forHTTPHeaderField: "If-Range") == "\"v1\"")
    }
}

// MARK: - Helpers

/// A server that supports HTTP range requests, and does what the test scripts
/// it to do, one step per request.
private final class _RangeServer: DataLoading, @unchecked Sendable {
    enum Step {
        /// Responds with "200 OK" and fails with `networkConnectionLost` after
        /// sending the given number of bytes.
        case fail(after: Int)
        /// Responds with "200 OK", sends the given number of bytes in a single
        /// chunk, and never completes.
        case stall(after: Int)
        /// Responds with "206 Partial Content" to a "Range" request with a
        /// matching "If-Range", or with "200 OK" to anything else.
        case serve
        /// Ignores the "Range" header and sends the whole resource with "200 OK".
        case ignoreRange
        /// Fails before sending a response.
        case failBeforeResponse
    }

    /// The resource the server has, and the validator it reports for it.
    var resource: (data: Data, validator: [String: String]) {
        get { lock.withLock { _resource } }
        set { lock.withLock { _resource = newValue } }
    }
    var steps: [Step] {
        get { lock.withLock { _steps } }
        set { lock.withLock { _steps = newValue } }
    }
    var requests: [URLRequest] { lock.withLock { _requests } }
    var cancelCount: Int { lock.withLock { _cancelCount } }

    private let lock = NSLock()
    private var _resource: (data: Data, validator: [String: String])
    private var _steps: [Step] = []
    private var _requests: [URLRequest] = []
    private var _cancelCount = 0

    init(data: Data, validator: [String: String]) {
        self._resource = (data, validator)
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let (step, (data, validator)) = lock.withLock {
            _requests.append(request)
            return (_steps.isEmpty ? Step.serve : _steps.removeFirst(), _resource)
        }
        let cancellable = AnonymousCancellable { [weak self] in
            self?.lock.withLock { self?._cancelCount += 1 }
        }

        func headers(_ extra: [String: String]) -> [String: String] {
            validator.merging(extra) { $1 }.merging(["Accept-Ranges": "bytes"]) { $1 }
        }
        func makeResponse(statusCode: Int, headers: [String: String]) -> HTTPURLResponse {
            HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
        }
        func send(_ range: Range<Int>, _ response: URLResponse) {
            for chunk in _createChunks(for: data[range], size: 4096) {
                didReceiveData(chunk, response)
            }
        }
        let ok = makeResponse(statusCode: 200, headers: headers(["Content-Length": "\(data.count)"]))

        switch step {
        case .fail(let count):
            send(0..<count, ok)
            completion(URLError(.networkConnectionLost))
        case .stall(let count):
            didReceiveData(data[0..<count], ok)
        case .ignoreRange:
            send(0..<data.count, ok)
            completion(nil)
        case .failBeforeResponse:
            completion(URLError(.notConnectedToInternet))
        case .serve:
            guard let offset = resumeOffset(for: request, data: data, validator: validator) else {
                send(0..<data.count, ok)
                completion(nil)
                return cancellable
            }
            let partial = makeResponse(statusCode: 206, headers: headers([
                "Content-Range": "bytes \(offset)-\(data.count - 1)/\(data.count)",
                "Content-Length": "\(data.count - offset)"
            ]))
            send(offset..<data.count, partial)
            completion(nil)
        }
        return cancellable
    }

    /// Returns the offset to resume from if the request asks for a range and
    /// its validator matches the resource.
    private func resumeOffset(for request: URLRequest, data: Data, validator: [String: String]) -> Int? {
        guard let range = request.value(forHTTPHeaderField: "Range"),
              let ifRange = request.value(forHTTPHeaderField: "If-Range"),
              ifRange == validator["ETag"],
              let offset = _groups(regex: "bytes=(\\d+)-", in: range).first.flatMap({ Int($0) }),
              offset < data.count else {
            return nil
        }
        return offset
    }
}

private final class _ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [ImageTask.Progress] = []

    var values: [ImageTask.Progress] { lock.withLock { _values } }

    func append(_ value: ImageTask.Progress) {
        lock.withLock { _values.append(value) }
    }
}

private final class _RecordingDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    /// The attempts, starting with 1, to reject.
    var failingAttempts: Set<Int> {
        get { lock.withLock { _failingAttempts } }
        set { lock.withLock { _failingAttempts = newValue } }
    }
    var requests: [URLRequest] { lock.withLock { _requests } }

    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private var _failingAttempts: Set<Int> = []

    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        let isRejected = lock.withLock {
            _requests.append(urlRequest)
            return _failingAttempts.contains(_requests.count)
        }
        if isRejected {
            throw URLError(.userAuthenticationRequired)
        }
        return urlRequest
    }
}
