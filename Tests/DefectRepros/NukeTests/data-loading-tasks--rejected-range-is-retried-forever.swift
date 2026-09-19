// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: when the server rejects a resumed request ("416 Range Not
// Satisfiable"), the pipeline keeps the resumable data and sends the same
// "Range" again on every following attempt, so the image can't be loaded until
// the entry is evicted from the (in-memory, shared) resumable data storage.
//
// Sources/Nuke/Tasks/TaskFetchOriginalData.swift `tryToSaveResumableData()`:
//
//     } else if let resumableData {
//         // The request ended before the server responded – put the data that
//         // `performDataLoad` took out of the storage back where it was.
//         ResumableDataStorage.shared.storeResumableData(resumableData, ...)
//     }
//
// The default `DataLoader` validates the status code as soon as the response
// arrives and fails with `DataLoader.Error.statusCodeUnacceptable(416)`
// without ever handing the response to the pipeline. `urlResponse` stays
// `nil`, so the pipeline takes the "before the server responded" branch and
// puts the rejected range back, although the server did respond – and
// rejected exactly that range. (A 416 happens, for example, with a server that
// honors "Range" but not "If-Range" after the resource got shorter.)
//
// Expected: after the 416, the next attempt asks for the whole resource.
// Actual:   every attempt sends "Range: bytes=10000-" and fails with 416.

@Suite(.timeLimit(.minutes(5)), .serialized)
struct RejectedRangeIsRetriedForeverBugTests {
    @Test func rangeRejectedByTheServerIsNotSentAgain() async throws {
        // GIVEN a real `DataLoader` talking to a server that serves the first
        // 10000 bytes and drops the connection, then rejects every range
        let url = URL(string: "nuke-range-bug://example.com/image.jpeg")!
        _RangeRejectingProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [_RangeRejectingProtocol.self]
        let pipeline = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: configuration)
            $0.imageCache = nil
        }

        // WHEN the download fails once the pipeline has the first 10000 bytes...
        let received = TestExpectation()
        let first = pipeline.makeStartedImageTask(with: ImageRequest(url: url), isDataTask: true) { event, _ in
            if case .progress = event { received.fulfill() }
        }
        await received.wait()
        _RangeRejectingProtocol.dropConnection()
        _ = try? await first.response

        // ...and is resumed twice
        _ = try? await pipeline.data(for: ImageRequest(url: url))
        let result = try? await pipeline.data(for: ImageRequest(url: url))

        // THEN
        let ranges = _RangeRejectingProtocol.ranges
        #expect(ranges.count == 3)
        #expect(ranges.first == .some(nil))
        #expect(ranges.dropFirst().first == "bytes=10000-")
        // The third attempt shouldn't repeat the range the server rejected...
        #expect(ranges.last == .some(nil))
        // ...and gets the image
        #expect(result?.0 == Test.data)
    }
}

private final class _RangeRejectingProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _ranges: [String?] = []

    nonisolated(unsafe) private static var _stalled: _RangeRejectingProtocol?

    static var ranges: [String?] { lock.withLock { _ranges } }
    static func reset() { lock.withLock { _ranges = []; _stalled = nil } }

    static func dropConnection() {
        let stalled = lock.withLock { _stalled.take() }
        if let stalled {
            stalled.client?.urlProtocol(stalled, didFailWithError: URLError(.networkConnectionLost))
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "nuke-range-bug"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let range = request.value(forHTTPHeaderField: "Range")
        let attempt = Self.lock.withLock { () -> Int in
            Self._ranges.append(range)
            return Self._ranges.count
        }
        let data = Test.data
        let url = request.url!
        if range != nil {
            let response = HTTPURLResponse(url: url, statusCode: 416, httpVersion: "HTTP/1.1", headerFields: ["Content-Range": "bytes */\(data.count)"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Length": "\(data.count)",
            "Accept-Ranges": "bytes",
            "ETag": "\"v1\""
        ])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if attempt == 1 {
            // The connection "drops" when the test says so: a failure reported
            // in the same breath makes the session discard the bytes.
            client?.urlProtocol(self, didLoad: data[0..<10000])
            Self.lock.withLock { Self._stalled = self }
        } else {
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
