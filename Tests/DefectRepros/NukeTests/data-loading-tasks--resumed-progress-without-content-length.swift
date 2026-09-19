// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: a resumed download whose "206 Partial Content" response has no
// "Content-Length" (chunked transfer, `expectedContentLength == -1`) reports a
// progress total that is *smaller* than the bytes already received, so the
// task reads as 100% complete from its first chunk.
//
// Sources/Nuke/Tasks/TaskFetchOriginalData.swift `dataTask(didReceiveData:response:)`:
//
//     TaskProgress(completed: Int64(data.count), total: response.expectedContentLength + resumedDataCount)
//
// With `expectedContentLength == -1` the total is `resumedDataCount - 1`. The
// diagnostics code a few lines below guards the same sum with
// `urlResponse.expectedContentLength >= 0`; the progress doesn't.
//
// Resource: 22789 bytes. Attempt 1 fails after 10000 bytes. Attempt 2 is a 206
// without "Content-Length" that sends the remaining 12789 bytes in 4 KB chunks.
//
// Expected: while the download is incomplete, `Progress.fraction < 1` and
//           `total` is never below `completed` (an unknown total should be
//           reported as unknown, the way a non-resumed download reports -1).
// Actual:   the first progress event is `completed: 14096, total: 9999`,
//           `fraction == 1`.

@Suite(.timeLimit(.minutes(5)))
struct ResumedProgressWithoutContentLengthBugTests {
    @Test func progressOfAResumedDownloadWithUnknownLengthIsNotComplete() async throws {
        // GIVEN a download that failed after 10000 bytes
        let server = _BugChunkedRangeServer(data: Test.data)
        let pipeline = ImagePipeline {
            $0.dataLoader = server
            $0.imageCache = nil
        }
        _ = try? await pipeline.data(for: Test.request)

        // WHEN it's resumed by a response without "Content-Length"
        let progress = _BugProgressRecorder()
        let task = pipeline.makeStartedImageTask(with: Test.request, isDataTask: true) { event, _ in
            if case .progress(let value) = event { progress.append(value) }
        }
        let response = try await task.response
        #expect(response.container.data == Test.data)
        #expect((response.urlResponse as? HTTPURLResponse)?.statusCode == 206)

        // THEN
        let values = progress.values
        #expect(values.count > 1)
        for value in values.dropLast() {
            #expect(value.fraction < 1, "\(value)")
            #expect(value.total <= 0 || value.total >= value.completed, "\(value)")
        }
    }
}

private final class _BugProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [ImageTask.Progress] = []
    var values: [ImageTask.Progress] { lock.withLock { _values } }
    func append(_ value: ImageTask.Progress) { lock.withLock { _values.append(value) } }
}

/// Fails the first request after 10000 bytes; answers a matching "Range"
/// request with a "206 Partial Content" that has no "Content-Length".
private final class _BugChunkedRangeServer: DataLoading, @unchecked Sendable {
    let data: Data
    private let lock = NSLock()
    private var attempt = 0

    init(data: Data) {
        self.data = data
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let attempt = lock.withLock { () -> Int in
            self.attempt += 1
            return self.attempt
        }
        let headers = ["Accept-Ranges": "bytes", "ETag": "\"v1\""]
        if attempt == 1 {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers.merging(["Content-Length": "\(data.count)"]) { $1 })!
            didReceiveData(data[0..<10000], response)
            completion(URLError(.networkConnectionLost))
        } else if let range = request.value(forHTTPHeaderField: "Range"), let offset = Int(range.dropFirst("bytes=".count).dropLast()) {
            let response = HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: headers.merging(["Content-Range": "bytes \(offset)-\(data.count - 1)/\(data.count)"]) { $1 })!
            precondition(response.expectedContentLength == -1)
            var start = offset
            while start < data.count {
                let end = min(start + 4096, data.count)
                didReceiveData(data[start..<end], response)
                start = end
            }
            completion(nil)
        } else {
            completion(URLError(.badServerResponse))
        }
        return AnonymousCancellable {}
    }
}
