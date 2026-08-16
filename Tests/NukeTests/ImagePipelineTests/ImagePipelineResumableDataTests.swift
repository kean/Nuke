// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineResumableDataTests {
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
            let (task, progress) = await pipeline.recordProgress(for: Test.request)
            initialProgress = progress
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
        let (task2, remainingProgress) = await pipeline.recordProgress(for: Test.request)
        _ = try await task2.response

        #expect(remainingProgress == [
            ImageTask.Progress(completed: 15196, total: 22789),
            ImageTask.Progress(completed: 18995, total: 22789),
            ImageTask.Progress(completed: 22789, total: 22789)
        ])
    }

    /// On a "206 Partial Content" response, `expectedContentLength` covers only
    /// the remaining bytes while the accumulated data already contains the
    /// resumed prefix. The guard that decides whether to give the decoder a
    /// chance to produce a preview used to compare the two directly, so it was
    /// never satisfied and the resumed download produced no previews at all.
    @Test func previewsAreDeliveredWhenTheDownloadIsResumed() async throws {
        // GIVEN a pipeline with progressive decoding enabled
        let dataLoader = _MockResumableProgressiveDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
        }

        // GIVEN an initial download that delivers one scan and then fails
        var initialPreviews: [ImageResponse] = []
        let initialTask = pipeline.imageTask(with: Test.request)
        for await preview in initialTask.previews {
            initialPreviews.append(preview)
        }
        await #expect(throws: ImagePipeline.Error.self) {
            try await initialTask.response
        }
        #expect(initialPreviews.count == 1)

        // WHEN the download is resumed with "206 Partial Content"
        var previews: [ImageResponse] = []
        let task = pipeline.imageTask(with: Test.request)
        for await preview in task.previews {
            previews.append(preview)
        }
        let response = try await task.response

        // THEN the remaining scans are still delivered as previews
        #expect(dataLoader.isResumed)
        #expect(previews.count == 1)
        #expect(previews.allSatisfy { $0.container.isPreview })

        // THEN the final image is produced
        #expect(!response.container.isPreview)
    }

    @Test func thatResumableDataIsntSavedIfCancelledWhenDownloadIsCompleted() async throws {
        // GIVEN an initial partial download that fails and stores resumable data
        _ = try? await pipeline.imageTask(with: Test.request).response

        // WHEN the download is resumed and completes successfully (all bytes delivered)
        _ = try await pipeline.imageTask(with: Test.request).response

        // THEN no resumable data remains in storage: the completed download doesn't
        // produce a partial entry (ResumableData init requires data.count < Content-Length).
        let stored = await ResumableDataStorage.shared.removeResumableData(
            for: ImageRequest(url: Test.url),
            pipeline: pipeline
        )
        #expect(stored == nil)
    }

    @Test func resumableDataIsKeptWhenCancelledBeforeServerResponds() async throws {
        // GIVEN a pipeline whose delegate can suspend right before data loading
        let delegate = _GatingDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        // GIVEN an initial partial download that stores resumable data
        _ = try? await pipeline.imageTask(with: Test.request).response

        // WHEN the next attempt is cancelled while `willLoadData` is suspended,
        // after the pipeline has already taken the data out of the storage
        let entered = AsyncGate(), proceed = AsyncGate()
        delegate.entered = entered
        delegate.proceed = proceed

        let task = pipeline.imageTask(with: Test.request)
        let response = Task { try await task.response }
        await entered.wait()
        task.cancel()
        await Task { @ImagePipelineActor in }.value
        proceed.open()
        _ = try? await response.value
        await Task { @ImagePipelineActor in }.value

        // THEN the resumable data is still there for the next attempt
        let stored = await ResumableDataStorage.shared.removeResumableData(
            for: ImageRequest(url: Test.url),
            pipeline: pipeline
        )
        #expect(stored != nil)
    }
}

private final class _GatingDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    var entered: AsyncGate?
    var proceed: AsyncGate?

    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        entered?.open()
        await proceed?.wait()
        return urlRequest
    }
}

/// Serves a progressive JPEG in three scans: the first attempt delivers the
/// first scan and fails, the resumed attempt delivers the rest with
/// "206 Partial Content".
private final class _MockResumableProgressiveDataLoader: DataLoading, @unchecked Sendable {
    let data = Test.data(name: "progressive", extension: "jpeg")
    let eTag = "img_01"

    /// `true` when the server accepted the "If-Range" header.
    private(set) var isResumed = false

    func loadData(with request: URLRequest,
                  didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                  completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let chunks = _createChunks(for: data, size: data.count / 3)

        func makeResponse(statusCode: Int, headerFields: [String: String]) -> HTTPURLResponse {
            var headerFields = headerFields
            headerFields["Accept-Ranges"] = "bytes"
            headerFields["ETag"] = eTag
            return HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headerFields)!
        }

        if let range = request.allHTTPHeaderFields?["Range"], request.allHTTPHeaderFields?["If-Range"] == eTag {
            isResumed = true

            // The client already has the first chunk – serve the remaining ones.
            let offset = Int(_groups(regex: "bytes=(\\d*)-", in: range)[0])!
            let remainingChunks = chunks.filter { $0.startIndex >= offset }
            let remainingCount = data.count - offset

            // "Content-Length" of a partial response covers the remaining bytes only.
            let response = makeResponse(statusCode: 206, headerFields: [
                "Content-Range": "bytes \(offset)-\(data.count - 1)/\(data.count)",
                "Content-Length": "\(remainingCount)"
            ])
            for chunk in remainingChunks {
                didReceiveData(chunk, response)
            }
            completion(nil)
        } else {
            // Serve the first chunk and fail mid-download.
            let response = makeResponse(statusCode: 200, headerFields: ["Content-Length": "\(data.count)"])
            didReceiveData(chunks[0], response)
            completion(URLError(.networkConnectionLost))
        }
        return AnonymousCancellable {}
    }
}

private class _MockResumableDataLoader: DataLoading, @unchecked Sendable {
    let data: Data = Test.data(name: "fixture", extension: "jpeg")
    let eTag: String = "img_01"

    func loadData(with request: URLRequest,
                  didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                  completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let headers = request.allHTTPHeaderFields
        let data = self.data
        let eTag = self.eTag

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
            guard validator == eTag else {
                completion(URLError(.cancelled))
                return AnonymousCancellable {}
            }
            let remainingData = data[Int(offset)!...]
            let chunks = Array(_createChunks(for: remainingData, size: data.count / 6 + 1))
            for chunk in chunks {
                let (chunkData, response) = sendChunk(chunk, of: remainingData, statusCode: 206)
                didReceiveData(chunkData, response)
            }
            completion(nil)
        } else {
            var chunks = Array(_createChunks(for: data, size: data.count / 6 + 1))
            chunks.removeLast(chunks.count / 2)
            for chunk in chunks {
                let (chunkData, response) = sendChunk(chunk, of: data, statusCode: 200)
                didReceiveData(chunkData, response)
            }
            completion(NSError(domain: NSURLErrorDomain, code: Foundation.URLError.networkConnectionLost.rawValue, userInfo: [:]))
        }
        return AnonymousCancellable {}
    }
}
