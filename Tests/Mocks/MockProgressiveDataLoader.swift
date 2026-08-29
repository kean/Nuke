// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

// One-shot data loader that servers data split into chunks, only send one chunk
// per one `resume()` call.
final class MockProgressiveDataLoader: DataLoading, @unchecked Sendable {
    let urlResponse: HTTPURLResponse
    var chunks: [Data]
    let data = Test.data(name: "progressive", extension: "jpeg")

    private var _didReceiveData: (@Sendable (Data, URLResponse) -> Void)?
    private var _completion: (@Sendable (Error?) -> Void)?

    /// Serves the first chunk from `loadData` without waiting for `resume()`.
    ///
    /// Set to `false` in the tests that serve the next chunk only when they
    /// receive a preview: subscribing to `ImageTask/previews` reaches the
    /// pipeline actor asynchronously and the previews produced before it lands
    /// are not replayed, so such a test deadlocks if it loses the first one.
    /// See `ImageTask/subscribedPreviews()`.
    var servesFirstChunkAutomatically = true

    /// Both are only ever touched on the main queue, which is what serializes
    /// them against `loadData` running on the pipeline actor.
    private var isLoading = false
    private var pendingResumeCount = 0

    init() {
        self.urlResponse = HTTPURLResponse(url: Test.url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(data.count)"])!
        self.chunks = Array(_createChunks(for: data, size: data.count / 3))
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
            self._didReceiveData = didReceiveData
        self._completion = completion
        DispatchQueue.main.async {
            self.isLoading = true
            if self.servesFirstChunkAutomatically {
                self.serveNextChunk()
            }
            // Serve whatever was requested before loading started.
            let pending = self.pendingResumeCount
            self.pendingResumeCount = 0
            for _ in 0..<pending {
                self.serveNextChunk()
            }
        }
        return _NoOpCancellable()
    }

    func resumeServingChunks(_ count: Int) {
        for _ in 0..<count {
            serveNextChunk()
        }
    }

    func serveNextChunk() {
        guard let chunk = chunks.first else { return }
        chunks.removeFirst()
        _didReceiveData?(chunk, urlResponse)
        if chunks.isEmpty {
            _completion?(nil)
        }
    }

    // Serves the next chunk.
    func resume(_ completed: @escaping @Sendable () -> Void = {}) {
        DispatchQueue.main.async {
            guard self.isLoading else {
                // `loadData` hasn't been called yet, and serving now would drop
                // the chunk – there is nobody to hand it to.
                self.pendingResumeCount += 1
                return
            }
            if let chunk = self.chunks.first {
                self.chunks.removeFirst()
                self._didReceiveData?(chunk, self.urlResponse)
                if self.chunks.isEmpty {
                    self._completion?(nil)
                    completed()
                }
            }
        }
    }
}

private final class _NoOpCancellable: Cancellable {
    func cancel() {}
}
