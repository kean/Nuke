// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

/// A server that supports HTTP range requests, and does what the test scripts
/// it to do, one step per request.
final class MockRangeServer: DataLoading, @unchecked Sendable {
    enum Step {
        /// Responds the way `serve` does, and fails with
        /// `networkConnectionLost` once it has sent the resource up to the
        /// given offset.
        case fail(after: Int)
        /// Responds with "200 OK", sends the given number of bytes in a single
        /// chunk, and never completes.
        case stall(after: Int)
        /// Responds with "206 Partial Content" to a "Range" request with a
        /// matching "If-Range", or with "200 OK" to anything else.
        case serve
        /// Same as `serve`, but advertises the given "Content-Length".
        case serveAdvertising(contentLength: String)
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
    /// The size of the chunks it sends the data in, 4096 bytes by default.
    /// `stall` sends a single one.
    var chunkSize: Int {
        get { lock.withLock { _chunkSize } }
        set { lock.withLock { _chunkSize = newValue } }
    }
    var requests: [URLRequest] { lock.withLock { _requests } }
    var cancelCount: Int { lock.withLock { _cancelCount } }

    private let lock = NSLock()
    private var _resource: (data: Data, validator: [String: String])
    private var _steps: [Step] = []
    private var _chunkSize = 4096
    private var _requests: [URLRequest] = []
    private var _cancelCount = 0

    init(data: Data, validator: [String: String]) {
        self._resource = (data, validator)
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let (step, (data, validator), chunkSize) = lock.withLock {
            _requests.append(request)
            return (_steps.isEmpty ? Step.serve : _steps.removeFirst(), _resource, _chunkSize)
        }
        let cancellable = MockRangeServerTask { [weak self] in
            self?.lock.withLock { self?._cancelCount += 1 }
        }

        func headers(_ extra: [String: String]) -> [String: String] {
            validator.merging(extra) { $1 }.merging(["Accept-Ranges": "bytes"]) { $1 }
        }
        func makeResponse(statusCode: Int, headers: [String: String]) -> HTTPURLResponse {
            HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
        }
        /// The response that honors the "Range" of the request, if it can,
        /// and the offset to send the resource from.
        func makeRangeResponse(contentLength: String? = nil) -> (HTTPURLResponse, Int) {
            guard let offset = resumeOffset(for: request, data: data, validator: validator) else {
                return (makeResponse(statusCode: 200, headers: headers(["Content-Length": contentLength ?? "\(data.count)"])), 0)
            }
            let partial = makeResponse(statusCode: 206, headers: headers([
                "Content-Range": "bytes \(offset)-\(data.count - 1)/\(data.count)",
                "Content-Length": contentLength ?? "\(data.count - offset)"
            ]))
            return (partial, offset)
        }
        func send(_ range: Range<Int>, _ response: URLResponse) {
            for chunk in _createChunks(for: data[range], size: chunkSize) {
                didReceiveData(chunk, response)
            }
        }
        let ok = makeResponse(statusCode: 200, headers: headers(["Content-Length": "\(data.count)"]))

        switch step {
        case .fail(let end):
            let (response, offset) = makeRangeResponse()
            send(offset..<end, response)
            completion(URLError(.networkConnectionLost))
        case .stall(let count):
            didReceiveData(data[0..<count], ok)
        case .ignoreRange:
            send(0..<data.count, ok)
            completion(nil)
        case .failBeforeResponse:
            completion(URLError(.notConnectedToInternet))
        case .serve, .serveAdvertising:
            let (response, offset) = makeRangeResponse(contentLength: contentLength(for: step))
            send(offset..<data.count, response)
            completion(nil)
        }
        return cancellable
    }

    private func contentLength(for step: Step) -> String? {
        if case .serveAdvertising(let contentLength) = step { contentLength } else { nil }
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

private struct MockRangeServerTask: Cancellable {
    let onCancel: @Sendable () -> Void

    func cancel() {
        onCancel()
    }
}
