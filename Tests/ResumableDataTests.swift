// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

private let _data = Data(count: 1000)

private func _makeResponse(statusCode: Int = 200, headers: [String: String]? = nil) -> HTTPURLResponse {
    return HTTPURLResponse(url: defaultURL, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
}

class ResumableDataCreationTests: XCTestCase {
    // MARK: Positive Tests

    func testCreateWithETag() {
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "ETag": "1234"]
        )
        let data = ResumableData(response: response, data: _data)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.data.count, 1000)
        XCTAssertEqual(data?.validator, "1234")
    }

    func testCreateWithETagSpelledIncorrectly() {
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Etag": "1234"]
        )
        let data = ResumableData(response: response, data: _data)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.data.count, 1000)
        XCTAssertEqual(data?.validator, "1234")
    }

    func testCreateWithLastModified() {
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Last-Modified": "Wed, 21 Oct 2015 07:28:00 GMT"]
        )
        let data = ResumableData(response: response, data: _data)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.data.count, 1000)
        XCTAssertEqual(data?.validator, "Wed, 21 Oct 2015 07:28:00 GMT")
    }

    func testCreateWithBothValidators() {
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "ETag": "1234",
            "Last-Modified": "Wed, 21 Oct 2015 07:28:00 GMT"]
        )
        let data = ResumableData(response: response, data: _data)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.data.count, 1000)
        XCTAssertEqual(data?.validator, "1234")
    }

    // We should store resumable data not just for statuc code "200 OK", but also
    // for "206 Partial Content" in case the resumed download fails.
    func testCreateWithStatusCodePartialContent() {
        let response = _makeResponse(statusCode: 206, headers: [
            "Accept-Ranges": "bytes",
            "ETag": "1234"]
        )
        let data = ResumableData(response: response, data: _data)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.data.count, 1000)
        XCTAssertEqual(data?.validator, "1234")
    }

    // MARK: Negative Tests

    func testCreateWithEmptyData() {
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "ETag": "1234"]
        )
        let data = ResumableData(response: response, data: Data())
        XCTAssertNil(data)
    }

    func testCreateWithNotHTTPResponse() {
        let response = URLResponse(url: defaultURL, mimeType: "jpeg", expectedContentLength: 10000, textEncodingName: nil)
        let data = ResumableData(response: response, data: _data)
        XCTAssertNil(data)
    }

    func testCreateWithInvalidStatusCode() {
        let response = _makeResponse(statusCode: 304, headers: [
            "Accept-Ranges": "bytes",
            "ETag": "1234"]
        )
        let data = ResumableData(response: response, data: _data)
        XCTAssertNil(data)
    }

    func testCreateWithMissingValidator() {
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes"]
        )
        let data = ResumableData(response: response, data: _data)
        XCTAssertNil(data)
    }

    func testCreateWithMissingAcceptRanges() {
        let response = _makeResponse(headers: [
            "ETag": "1234"]
        )
        let data = ResumableData(response: response, data: _data)
        XCTAssertNil(data)
    }

    func testCreateWithAcceptRangesNone() {
        let response = _makeResponse(headers: [
            "Accept-Ranges": "none",
            "ETag": "1234"]
        )
        let data = ResumableData(response: response, data: _data)
        XCTAssertNil(data)
    }
}

class ResumableDataResumingTests: XCTestCase {
    func testResumingRequst() {
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "ETag": "1234"]
        )
        let data = ResumableData(response: response, data: _data)!
        var request = URLRequest(url: defaultURL)
        data.resume(request: &request)

        // Check that we've set both required "range" filed
        XCTAssertEqual(request.allHTTPHeaderFields?["Range"], "bytes=1000-")
        XCTAssertEqual(request.allHTTPHeaderFields?["If-Range"], "1234")
    }

    func testCheckingResumedResponse() {
        XCTAssertTrue(ResumableData.isResumedResponse(_makeResponse(statusCode: 206)))

        // Need to load new data
        XCTAssertFalse(ResumableData.isResumedResponse(_makeResponse(statusCode: 200)))

        XCTAssertFalse(ResumableData.isResumedResponse(_makeResponse(statusCode: 404)))
    }
}
