// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG (docs vs behavior): progressive decoding never produces a preview for a
// response that doesn't report its length (`expectedContentLength == -1`,
// `NSURLResponseUnknownLength`, e.g. chunked transfer encoding or an HTTP/2
// response without "Content-Length").
//
// Sources/Nuke/Tasks/TaskFetchOriginalData.swift `dataTask(didReceiveData:response:)`:
//
//     // If the image hasn't been fully loaded yet, give decoder a chance
//     // to decode the data chunk. In case `expectedContentLength` is `0`,
//     // progressive decoding doesn't run.
//     guard data.count < response.expectedContentLength + resumedDataCount else { return }
//     send(value: (data, response))
//
// `data.count < -1` is never true, so the partial data is never handed to the
// decoder. The docs promise previews "as data arrives"
// (Documentation/Nuke.docc/Extensions/ImagePipeline-Extension.md, "Progressive
// Decoding"; `DataLoading` docs: "The pipeline uses these chunks for
// progressive decoding") without a "Content-Length" requirement. The length
// isn't needed to decide: the completion is what marks the final chunk.
//
// Expected: the same previews with and without "Content-Length".
// Actual:   1 preview with it (control), 0 without.

@Suite(.timeLimit(.minutes(5)))
struct NoPreviewsWithoutContentLengthBugTests {
    @Test(arguments: [true, false])
    func progressiveJPEGProducesPreviews(reportsContentLength: Bool) async throws {
        // GIVEN a progressive JPEG delivered in three chunks
        let pipeline = ImagePipeline {
            $0.dataLoader = _BugChunkedLoader(reportsContentLength: reportsContentLength)
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
        }

        // WHEN
        let previews = _BugPreviewCounter()
        let task = pipeline.makeStartedImageTask(with: Test.request) { event, _ in
            if case .preview = event { previews.increment() }
        }
        let response = try await task.response

        // THEN
        #expect(!response.container.isPreview)
        #expect(previews.value > 0, "reportsContentLength: \(reportsContentLength)")
    }
}

private final class _BugPreviewCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}

private final class _BugChunkedLoader: DataLoading, @unchecked Sendable {
    let reportsContentLength: Bool

    init(reportsContentLength: Bool) {
        self.reportsContentLength = reportsContentLength
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let data = Test.data(name: "progressive", extension: "jpeg")
        let headers = reportsContentLength ? ["Content-Length": "\(data.count)"] : [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        precondition(response.expectedContentLength == (reportsContentLength ? Int64(data.count) : -1))
        for chunk in _createChunks(for: data, size: data.count / 3) {
            didReceiveData(chunk, response)
        }
        completion(nil)
        return AnonymousCancellable {}
    }
}
