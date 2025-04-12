// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

@ImagePipelineActor
@Suite struct ImagePipelineResumableDataTests {
    private var dataLoader: _MockResumableDataLoader!
    private var pipeline: ImagePipeline!

    init() {
        dataLoader = _MockResumableDataLoader()
        ResumableDataStorage.shared.removeAllResponses()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    @Test func thatProgressIsReported() async throws {
        // Given an initial request failed mid download
        var recorded: [ImageTask.Progress] = []
        let request = Test.request

        // When
        for await progress in pipeline.imageTask(with: request).progress {
            recorded.append(progress)
        }

        // Then
        #expect(recorded == [
            ImageTask.Progress(completed: 3799, total: 22789),
            ImageTask.Progress(completed: 7598, total: 22789),
            ImageTask.Progress(completed: 11397, total: 22789)
        ])

        // When restarting the request
        recorded = []
        for await progress in pipeline.imageTask(with: request).progress {
            recorded.append(progress)
        }

        // Then remaining progress is reported
        #expect(recorded == [
            ImageTask.Progress(completed: 15196, total: 22789),
            ImageTask.Progress(completed: 18995, total: 22789),
            ImageTask.Progress(completed: 22789, total: 22789)
        ])
    }
}

private class _MockResumableDataLoader: MockDataLoading, DataLoading, @unchecked Sendable {
    private let queue = DispatchQueue(label: "_MockResumableDataLoader")

    let data: Data = Test.data(name: "fixture", extension: "jpeg")
    let eTag: String = "img_01"

    func loadData(for request: ImageRequest) -> AsyncThrowingStream<(Data, URLResponse), any Error> {
        AsyncThrowingStream { continuation in
            guard let urlRequest = request.urlRequest else {
                return continuation.finish(throwing: URLError(.badURL))
            }
            let task = loadData(with: urlRequest) { data, response in
                continuation.yield((data, response))
            } completion: { error in
                continuation.finish(throwing: error)
            }
            continuation.onTermination = { reason in
                switch reason {
                case .cancelled: task.cancel()
                default: break
                }
            }
        }
    }

    func loadData(with request: URLRequest, didReceiveData: @Sendable @escaping (Data, URLResponse) -> Void, completion: @Sendable @escaping (Error?) -> Void) -> MockDataTaskProtocol {
        let headers = request.allHTTPHeaderFields

        let completion = completion
        let didReceiveData = didReceiveData

        func sendChunks(_ chunks: [Data], of data: Data, statusCode: Int) {
            @Sendable func sendChunk(_ chunk: Data) {
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

                didReceiveData(chunk, response)
            }

            var chunks = chunks
            while let chunk = chunks.first {
                chunks.removeFirst()
                queue.async {
                    sendChunk(chunk)
                }
            }
        }

        // Check if the client already has some resumable data available.
        if let range = headers?["Range"], let validator = headers?["If-Range"] {
            let offset = _groups(regex: "bytes=(\\d*)-", in: range)[0]
            #expect(offset != nil)

            #expect(validator == eTag, "Expected validator to be equal to ETag")
            guard validator == eTag else { // Expected ETag
                return _Task()
            }

            // Send remaining data in chunks
            let remainingData = data[Int(offset)!...]
            let chunks = Array(_createChunks(for: remainingData, size: data.count / 6 + 1))

            sendChunks(chunks, of: remainingData, statusCode: 206)
            queue.async {
                completion(nil)
            }
        } else {
            // Send half of chunks.
            var chunks = Array(_createChunks(for: data, size: data.count / 6 + 1))
            chunks.removeLast(chunks.count / 2)

            sendChunks(chunks, of: data, statusCode: 200)
            queue.async {
                completion(NSError(domain: NSURLErrorDomain, code: URLError.networkConnectionLost.rawValue, userInfo: [:]))
            }
        }

        return _Task()
    }

    private class _Task: MockDataTaskProtocol, @unchecked Sendable {
        func cancel() { }
    }
}
