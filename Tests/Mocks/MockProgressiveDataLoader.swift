// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

// One-shot data loader that servers data split into chunks, only send one chunk
// per one `resume()` call.
final class MockProgressiveDataLoader: DataLoading, @unchecked Sendable {
    let urlResponse: HTTPURLResponse
    let data = Test.data(name: "progressive", extension: "jpeg")

    // The tests drive the loader from multiple threads, so the mock has to be
    // thread safe.
    private let lock = NSLock()
    private var _chunks: [Data]
    private var _didReceiveData: (@Sendable (Data, URLResponse) -> Void)?
    private var _completion: (@Sendable (Error?) -> Void)?

    var chunks: [Data] { lock.withLock { _chunks } }

    init() {
        self.urlResponse = HTTPURLResponse(url: Test.url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(data.count)"])!
        self._chunks = Array(_createChunks(for: data, size: data.count / 3))
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        lock.withLock {
            self._didReceiveData = didReceiveData
            self._completion = completion
        }
        // Serve the first chunk immediately
        DispatchQueue.main.async {
            self.serveNextChunk()
        }
        return _NoOpCancellable()
    }

    func resumeServingChunks(_ count: Int) {
        for _ in 0..<count {
            serveNextChunk()
        }
    }

    /// Returns `true` if the served chunk was the last one.
    @discardableResult private func serveNextChunk() -> Bool {
        let (chunk, didReceiveData, completion): (Data?, (@Sendable (Data, URLResponse) -> Void)?, (@Sendable (Error?) -> Void)?) = lock.withLock {
            guard !_chunks.isEmpty else { return (nil, nil, nil) }
            let chunk = _chunks.removeFirst()
            return (chunk, _didReceiveData, _chunks.isEmpty ? _completion : nil)
        }
        guard let chunk else { return false }
        didReceiveData?(chunk, urlResponse)
        completion?(nil)
        return completion != nil
    }

    // Serves the next chunk.
    func resume(_ completed: @escaping @Sendable () -> Void = {}) {
        DispatchQueue.main.async {
            if self.serveNextChunk() {
                completed()
            }
        }
    }
}

private final class _NoOpCancellable: Cancellable {
    func cancel() {}
}
