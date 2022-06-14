// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

// One-shot data loader that servers data split into chunks, only send one chunk
// per one `resume()` call.
final class MockProgressiveDataLoader: DataLoading, @unchecked Sendable {
    let urlResponse: HTTPURLResponse
    var chunks: [Data]
    let data = Test.data(name: "progressive", extension: "jpeg")

    private var didReceiveResponse: (URLResponse) -> Void = { _ in }
    private var didReceiveData: (Data) -> Void = { _ in }
    private var completion: (Error?) -> Void = { _ in }

    init() {
        self.urlResponse = HTTPURLResponse(url: Test.url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(data.count)"])!
        self.chunks = Array(_createChunks(for: data, size: data.count / 3))
    }

#warning("TODO: simplify this")

    func data(for request: URLRequest) -> AsyncThrowingStream<DataTaskSequenceElement, Error> {
        AsyncThrowingStream { [self] continuation in
            loadData(with: request, didReceiveResponse: { response in
                continuation.yield(.respone(response))
            }, didReceiveData: { data in
                continuation.yield(.data(data))
            }, completion: { error in
                if let error = error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            })
        }
    }

    private func loadData(with request: URLRequest, didReceiveResponse: @escaping (URLResponse) -> Void, didReceiveData: @escaping (Data) -> Void, completion: @escaping (Error?) -> Void) {
        self.didReceiveResponse = didReceiveResponse
        self.didReceiveData = didReceiveData
        self.completion = completion
        DispatchQueue.main.async {
            self.didReceiveResponse(self.urlResponse)
        }
        resume()
    }

    func resumeServingChunks(_ count: Int) {
        for _ in 0..<count {
            serveNextChunk()
        }
    }

    func serveNextChunk() {
        guard let chunk = chunks.first else { return }
        chunks.removeFirst()
        didReceiveData(chunk)
        if chunks.isEmpty {
            completion(nil)
        }
    }

    // Serves the next chunk.
    func resume(_ completed: @escaping () -> Void = {}) {
        DispatchQueue.main.async {
            if let chunk = self.chunks.first {
                self.chunks.removeFirst()
                self.didReceiveData(chunk)
                if self.chunks.isEmpty {
                    self.completion(nil)
                    completed()
                }
            }
        }
    }
}
