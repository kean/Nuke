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
    private let pipeline: ImagePipeline

    init() {
        let server = _RangeServer(data: Test.data, validator: ["ETag": "\"v1\""])
        self.server = server
        self.pipeline = ImagePipeline {
            $0.dataLoader = server
            $0.imageCache = nil
        }
    }

    /// Foundation reports a "Content-Length" it can't represent as
    /// `Int64.max`, so adding the resumed bytes to it must not overflow.
    @Test func resumedResponseWithHugeContentLengthExceedsMaximumSize() async throws {
        // GIVEN a download that failed after 10000 bytes
        server.steps = [.fail(after: 10000), .serveAdvertising(contentLength: "99999999999999999999")]
        _ = try? await pipeline.data(for: Test.request)

        // WHEN the resumed response advertises a length above the limit
        await #expect(throws: ImagePipeline.Error.dataDownloadExceededMaximumSize) {
            try await pipeline.data(for: Test.request)
        }

        // THEN
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=10000-")
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
        /// Responds with "206 Partial Content" to a "Range" request with a
        /// matching "If-Range", or with "200 OK" to anything else.
        case serve
        /// Same as `serve`, but advertises the given "Content-Length".
        case serveAdvertising(contentLength: String)
    }

    var steps: [Step] {
        get { lock.withLock { _steps } }
        set { lock.withLock { _steps = newValue } }
    }
    var requests: [URLRequest] { lock.withLock { _requests } }

    private let lock = NSLock()
    private let data: Data
    private let validator: [String: String]
    private var _steps: [Step] = []
    private var _requests: [URLRequest] = []

    init(data: Data, validator: [String: String]) {
        self.data = data
        self.validator = validator
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let step = lock.withLock {
            _requests.append(request)
            return _steps.isEmpty ? Step.serve : _steps.removeFirst()
        }
        let data = self.data
        let cancellable = AnonymousCancellable {}

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

        switch step {
        case .fail(let count):
            send(0..<count, makeResponse(statusCode: 200, headers: headers(["Content-Length": "\(data.count)"])))
            completion(URLError(.networkConnectionLost))
        case .serve, .serveAdvertising:
            guard let offset = resumeOffset(for: request) else {
                let ok = makeResponse(statusCode: 200, headers: headers(["Content-Length": contentLength(for: step) ?? "\(data.count)"]))
                send(0..<data.count, ok)
                completion(nil)
                return cancellable
            }
            let partial = makeResponse(statusCode: 206, headers: headers([
                "Content-Range": "bytes \(offset)-\(data.count - 1)/\(data.count)",
                "Content-Length": contentLength(for: step) ?? "\(data.count - offset)"
            ]))
            send(offset..<data.count, partial)
            completion(nil)
        }
        return cancellable
    }

    private func contentLength(for step: Step) -> String? {
        if case .serveAdvertising(let contentLength) = step { contentLength } else { nil }
    }

    /// Returns the offset to resume from if the request asks for a range and
    /// its validator matches the resource.
    private func resumeOffset(for request: URLRequest) -> Int? {
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
