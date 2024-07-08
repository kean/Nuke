// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

// One-shot data loader that servers data split into chunks, only send one chunk
// per one `resume()` call.
public final class MockProgressiveDataLoader: DataLoading, @unchecked Sendable {
    let urlResponse: HTTPURLResponse
    var chunks: [Data]
    public let data = Test.data(name: "progressive", extension: "jpeg")

    class _MockTask: Cancellable, @unchecked Sendable {
        func cancel() {
            // Do nothing
        }
    }

    private var didReceiveData: (Data, URLResponse) -> Void = { _, _ in }
    private var completion: (Error?) -> Void = { _ in }

    public init() {
        self.urlResponse = HTTPURLResponse(url: Test.url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(data.count)"])!
        self.chunks = Array(_createChunks(for: data, size: data.count / 3))
    }

    public func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> Cancellable {
        self.didReceiveData = didReceiveData
        self.completion = completion
        self.resume()
        return _MockTask()
    }

    public func resumeServingChunks(_ count: Int) {
        for _ in 0..<count {
            serveNextChunk()
        }
    }

    public func serveNextChunk() {
        guard let chunk = chunks.first else { return }
        chunks.removeFirst()
        didReceiveData(chunk, urlResponse)
        if chunks.isEmpty {
            completion(nil)
        }
    }

    // Serves the next chunk.
    public func resume(_ completed: @escaping () -> Void = {}) {
        DispatchQueue.main.async {
            if let chunk = self.chunks.first {
                self.chunks.removeFirst()
                self.didReceiveData(chunk, self.urlResponse)
                if self.chunks.isEmpty {
                    self.completion(nil)
                    completed()
                }
            }
        }
    }
}
