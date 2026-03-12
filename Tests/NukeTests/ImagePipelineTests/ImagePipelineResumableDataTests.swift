// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite struct ImagePipelineResumableDataTests {
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

    @Test func thatResumableDataIsntSavedIfCancelledWhenDownloadIsCompleted() {

    }
}

private class _MockResumableDataLoader: DataLoading, @unchecked Sendable {
    private let queue = OperationQueue()

    let data: Data = Test.data(name: "fixture", extension: "jpeg")
    let eTag: String = "img_01"

    init() {
        queue.maxConcurrentOperationCount = 1
    }

    func loadData(with request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse) {
        let headers = request.allHTTPHeaderFields
        let data = self.data
        let eTag = self.eTag

        return try await withCheckedThrowingContinuation { continuation in
            let operation = BlockOperation {
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

                    guard validator == eTag else { return }

                    // Send remaining data in chunks
                    let remainingData = data[Int(offset)!...]
                    let chunks = Array(_createChunks(for: remainingData, size: data.count / 6 + 1))
                    let firstResult = sendChunk(chunks[0], of: remainingData, statusCode: 206)
                    let response = firstResult.1
                    let stream = AsyncThrowingStream<Data, Error> { streamContinuation in
                        streamContinuation.yield(firstResult.0)
                        for chunk in chunks.dropFirst() {
                            let result = sendChunk(chunk, of: remainingData, statusCode: 206)
                            streamContinuation.yield(result.0)
                        }
                        streamContinuation.finish()
                    }
                    continuation.resume(returning: (stream, response))
                } else {
                    // Send half of chunks.
                    var chunks = Array(_createChunks(for: data, size: data.count / 6 + 1))
                    chunks.removeLast(chunks.count / 2)

                    let firstResult = sendChunk(chunks[0], of: data, statusCode: 200)
                    let response = firstResult.1
                    let stream = AsyncThrowingStream<Data, Error> { streamContinuation in
                        streamContinuation.yield(firstResult.0)
                        for chunk in chunks.dropFirst() {
                            let result = sendChunk(chunk, of: data, statusCode: 200)
                            streamContinuation.yield(result.0)
                        }
                        streamContinuation.finish(throwing: NSError(domain: NSURLErrorDomain, code: Foundation.URLError.networkConnectionLost.rawValue, userInfo: [:]))
                    }
                    continuation.resume(returning: (stream, response))
                }
            }

            self.queue.addOperation(operation)
        }
    }
}
