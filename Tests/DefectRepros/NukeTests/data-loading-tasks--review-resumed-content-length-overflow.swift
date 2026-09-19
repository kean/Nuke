// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: a resumed download crashes the process with an arithmetic overflow when
// the "206 Partial Content" response advertises a `Content-Length` close to
// `Int64.max`. Foundation clamps any larger number to `Int64.max`, so a server
// that sends a garbage length such as "99999999999999999999" is enough.
//
// Sources/Nuke/Tasks/TaskFetchOriginalData.swift, `dataTask(didReceiveResponse:)`:
//
//     if let resumableData, ResumableData.isResumedResponse(response) {
//         ...
//         resumedDataCount = Int64(resumableData.data.count)
//         let expectedSize = response.expectedContentLength + resumedDataCount   // <- traps
//
// `Int64` addition traps on overflow. The same unchecked sum is repeated for
// the `maximumResponseDataSize` check, the progress total and the preview guard
// (`response.expectedContentLength + resumedDataCount`), so every one of them
// would trap as well. A download that isn't resumed never adds anything, which
// is why only the resumed path crashes. The size limit can't help: the trap
// happens before the limit is checked.
//
// Related: in the same resumed branch, `data.reserveCapacity(Int(expectedSize))`
// runs *before* the `maximumResponseDataSize` check, although the comment on
// that check says it exists "to avoid a large `reserveCapacity` allocation
// when the server reports a content length above the limit". A resumed 206
// that advertises, say, 100 GB therefore reserves 100 GB before the request is
// rejected. (That half is harmless on macOS, where the reservation is only
// virtual, so this repro covers the overflow.)
//
// Expected: the resumed request fails with `.dataDownloadExceededMaximumSize`
//           (the advertised size is far above the default limit).
// Actual:   the test process crashes: "Swift runtime failure: arithmetic
//           overflow" in `TaskFetchOriginalData.dataTask(didReceiveResponse:)`.

@Suite(.timeLimit(.minutes(5)))
struct ResumedContentLengthOverflowBugTests {
    @Test func resumedResponseAdvertisingAHugeLengthFailsInsteadOfCrashing() async throws {
        // GIVEN a download that failed after 10000 bytes and left resumable data
        let server = _HugeLengthRangeServer()
        let pipeline = ImagePipeline {
            $0.dataLoader = server
            $0.imageCache = nil
        }
        await #expect(throws: ImagePipeline.Error.self) {
            try await pipeline.data(for: Test.request)
        }

        // WHEN the server answers the resumed request with a 206 whose
        // Content-Length Foundation clamps to Int64.max
        await #expect(throws: ImagePipeline.Error.dataDownloadExceededMaximumSize) {
            try await pipeline.data(for: Test.request)
        }

        // THEN (not reached today – the process traps above)
        let resumed = try #require(server.requests.last)
        #expect(resumed.value(forHTTPHeaderField: "Range") == "bytes=10000-")
    }
}

/// The first request gets "200 OK" with the first 10000 bytes and fails; a
/// "Range" request gets "206 Partial Content" with a garbage Content-Length.
private final class _HugeLengthRangeServer: DataLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { _requests } }

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        lock.withLock { _requests.append(request) }
        let data = Test.data
        func response(_ statusCode: Int, _ headers: [String: String]) -> HTTPURLResponse {
            HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers.merging(["Accept-Ranges": "bytes", "ETag": "\"v1\""]) { $1 })!
        }
        if request.value(forHTTPHeaderField: "Range") == nil {
            didReceiveData(data[0..<10000], response(200, ["Content-Length": "\(data.count)"]))
            completion(URLError(.networkConnectionLost))
        } else {
            let partial = response(206, [
                "Content-Length": "99999999999999999999",
                "Content-Range": "bytes 10000-\(data.count - 1)/\(data.count)"
            ])
            didReceiveData(data[10000...], partial)
            completion(nil)
        }
        return AnonymousCancellable {}
    }
}
