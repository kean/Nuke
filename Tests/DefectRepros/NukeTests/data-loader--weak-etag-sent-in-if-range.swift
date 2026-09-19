// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: resumable downloads put a weak entity tag in "If-Range".
//
// Sources/Nuke/Internal/ResumableData.swift `_validator(from:)` returns the
// "ETag" header verbatim, and `resume(request:)` sends it as "If-Range".
// RFC 9110 §13.1.5 (formerly RFC 7233 §3.2): "A client MUST NOT generate an
// If-Range header field containing an entity tag that is marked as weak."
// A weak validator doesn't guarantee byte-for-byte identical content, which
// is what splicing a stored prefix onto a new range requires:
//
// - A compliant server compares If-Range with the strong comparison, which a
//   weak tag never passes, so it always answers "200 OK" with the full body:
//   the stored partial data can never be used, yet the pipeline keeps storing
//   it (up to the storage limits) and sending the range headers.
// - A lenient server (or proxy) that compares weakly answers "206" for a
//   representation that is only semantically equivalent (e.g. re-encoded), and
//   the pipeline splices bytes of two different files into one image.
//
// Servers commonly send weak ETags (e.g. nginx and Apache whenever they
// compress or transform the response).
//
// Expected: a weak ETag is not used as the "If-Range" validator (no resumable
//           data is created, or the request isn't made conditional on it).
// Actual:   "If-Range: W/\"abc\"".

@Suite(.timeLimit(.minutes(1)))
struct ResumableDataWeakETagBugTests {
    @Test func weakEntityTagIsNotSentInIfRange() {
        // GIVEN a partial download validated by a weak entity tag
        let response = HTTPURLResponse(url: Test.url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "ETag": "W/\"abc\""
        ])!
        let resumableData = ResumableData(response: response, data: Data(count: 1000))

        // WHEN
        var request = URLRequest(url: Test.url)
        resumableData?.resume(request: &request)

        // THEN
        let ifRange = request.value(forHTTPHeaderField: "If-Range")
        #expect(ifRange?.hasPrefix("W/") != true, "If-Range: \(ifRange ?? "nil")")
    }
}
