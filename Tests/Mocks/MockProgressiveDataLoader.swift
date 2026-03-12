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

    private var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation?

    init() {
        self.urlResponse = HTTPURLResponse(url: Test.url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(data.count)"])!
        self.chunks = Array(_createChunks(for: data, size: data.count / 3))
    }

    func loadData(with request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse) {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            self.streamContinuation = continuation
        }
        // Serve the first chunk immediately
        DispatchQueue.main.async {
            self.serveNextChunk()
        }
        return (stream, urlResponse)
    }

    func resumeServingChunks(_ count: Int) {
        for _ in 0..<count {
            serveNextChunk()
        }
    }

    func serveNextChunk() {
        guard let chunk = chunks.first else { return }
        chunks.removeFirst()
        streamContinuation?.yield(chunk)
        if chunks.isEmpty {
            streamContinuation?.finish()
        }
    }

    // Serves the next chunk.
    func resume(_ completed: @escaping @Sendable () -> Void = {}) {
        DispatchQueue.main.async {
            if let chunk = self.chunks.first {
                self.chunks.removeFirst()
                self.streamContinuation?.yield(chunk)
                if self.chunks.isEmpty {
                    self.streamContinuation?.finish()
                    completed()
                }
            }
        }
    }
}
