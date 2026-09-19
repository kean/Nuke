// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: a resumed download that fails again loses every byte it had.
//
// Sources/Nuke/Tasks/TaskFetchOriginalData.swift `tryToSaveResumableData()`
// builds `ResumableData(response: urlResponse, data: data)`. After a resume,
// `urlResponse` is the "206 Partial Content" response, whose
// `expectedContentLength` covers only the *remaining* bytes, while `data`
// already holds the resumed prefix plus what arrived since.
// `ResumableData.init` requires `data.count < response.expectedContentLength`,
// so as soon as prefix + received >= remaining, it returns `nil`. The previous
// `resumableData` was already set to `nil` in `dataTask(didReceiveResponse:)`,
// so nothing is stored and the next attempt downloads the whole image again.
//
// `ResumableDataTests.createWithStatusCodePartialContent` spells out the
// intent: "We should store resumable data not just for status code 200 OK,
// but also for 206 Partial Content in case the resumed download fails."
// The same prefix-vs-remaining mismatch was already fixed for the progressive
// preview guard (see `previewsAreDeliveredWhenTheDownloadIsResumed`).
//
// Resource: 22789 bytes. Attempt 1 fails after 8000 bytes (stored). Attempt 2
// resumes with "Range: bytes=8000-" (206, Content-Length 14789) and fails at
// offset 20000 (data = 20000 bytes, 20000 >= 14789).
//
// Expected: attempt 3 sends "Range: bytes=20000-".
// Actual:   attempt 3 sends no "Range" header and starts from scratch.

@Suite(.timeLimit(.minutes(5)))
struct ResumedDownloadFailureLosesResumableDataBugTests {
    @Test func resumedDownloadThatFailsAgainKeepsItsBytes() async throws {
        // GIVEN
        let server = _BugRangeServer(data: Test.data)
        server.steps = [.fail(atOffset: 8000), .resumeAndFail(atOffset: 20000), .serve]
        let pipeline = ImagePipeline {
            $0.dataLoader = server
            $0.imageCache = nil
        }

        // WHEN the download fails, is resumed, and fails again
        _ = try? await pipeline.data(for: Test.request)
        _ = try? await pipeline.data(for: Test.request)
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=8000-")

        // THEN the third attempt resumes from where the second one failed
        let (data, _) = try await pipeline.data(for: Test.request)
        #expect(data == Test.data)
        #expect(server.requests.count == 3)
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=20000-")
    }
}

private final class _BugRangeServer: DataLoading, @unchecked Sendable {
    enum Step {
        case fail(atOffset: Int)
        case resumeAndFail(atOffset: Int)
        case serve
    }

    let data: Data
    private let lock = NSLock()
    private var _steps: [Step] = []
    private var _requests: [URLRequest] = []

    var steps: [Step] {
        get { lock.withLock { _steps } }
        set { lock.withLock { _steps = newValue } }
    }
    var requests: [URLRequest] { lock.withLock { _requests } }

    init(data: Data) {
        self.data = data
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let step = lock.withLock { () -> Step in
            _requests.append(request)
            return _steps.isEmpty ? .serve : _steps.removeFirst()
        }
        func response(_ statusCode: Int, _ headers: [String: String]) -> HTTPURLResponse {
            HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers.merging(["Accept-Ranges": "bytes", "ETag": "\"v1\""]) { $1 })!
        }
        let offset = request.value(forHTTPHeaderField: "If-Range") == "\"v1\""
            ? request.value(forHTTPHeaderField: "Range").flatMap { Int($0.dropFirst("bytes=".count).dropLast()) }
            : nil
        switch step {
        case .fail(let end):
            didReceiveData(data[0..<end], response(200, ["Content-Length": "\(data.count)"]))
            completion(URLError(.networkConnectionLost))
        case .resumeAndFail(let end):
            let start = offset ?? 0
            didReceiveData(data[start..<end], response(206, ["Content-Length": "\(data.count - start)", "Content-Range": "bytes \(start)-\(data.count - 1)/\(data.count)"]))
            completion(URLError(.networkConnectionLost))
        case .serve:
            if let start = offset {
                didReceiveData(data[start...], response(206, ["Content-Length": "\(data.count - start)", "Content-Range": "bytes \(start)-\(data.count - 1)/\(data.count)"]))
            } else {
                didReceiveData(data, response(200, ["Content-Length": "\(data.count)"]))
            }
            completion(nil)
        }
        return AnonymousCancellable {}
    }
}
