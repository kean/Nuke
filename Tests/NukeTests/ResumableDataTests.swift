// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

// Test ResumableData directly to make sure it makes the right decisions based
// on HTTP flows.
@Suite struct ResumableDataTests {
    @Test func resumingRequest() {
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "ETag": "1234"
        ])
        let data = ResumableData(response: response, data: _data)!
        var request = URLRequest(url: Test.url)
        data.resume(request: &request)

        // Check that we've set both required "range" filed
        #expect(request.allHTTPHeaderFields?["Range"] == "bytes=1000-")
        #expect(request.allHTTPHeaderFields?["If-Range"] == "1234")
    }

    @Test func checkingResumedResponse() {
        #expect(ResumableData.isResumedResponse(_makeResponse(statusCode: 206)))

        // Need to load new data
        #expect(!ResumableData.isResumedResponse(_makeResponse(statusCode: 200)))

        #expect(!ResumableData.isResumedResponse(_makeResponse(statusCode: 404)))
    }

    // MARK: - Creation (Positive)

    @Test func createWithETag() throws {
        // Given
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "ETag": "1234"
        ])
        let data = try #require(ResumableData(response: response, data: _data))

        // Then
        #expect(data.data.count == 1000)
        #expect(data.validator == "1234")
    }

    @Test func createWithETagSpelledIncorrectly() throws {
        // Given
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "Etag": "1234"
        ])
        let data = try #require(ResumableData(response: response, data: _data))

        // Then
        #expect(data.data.count == 1000)
        #expect(data.validator == "1234")
    }

    @Test func createWithLastModified() throws {
        // Given
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "Last-Modified": "Wed, 21 Oct 2015 07:28:00 GMT"
        ])
        let data = try #require(ResumableData(response: response, data: _data))

        // Then
        #expect(data.data.count == 1000)
        #expect(data.validator == "Wed, 21 Oct 2015 07:28:00 GMT")
    }

    @Test func createWithBothValidators() throws {
        // Given
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "ETag": "1234",
            "Content-Length": "2000",
            "Last-Modified": "Wed, 21 Oct 2015 07:28:00 GMT"
        ])
        let data = try #require(ResumableData(response: response, data: _data))

        // Then
        #expect(data.data.count == 1000)
        #expect(data.validator == "1234")
    }

    // We should store resumable data not just for statuc code "200 OK", but also
    // for "206 Partial Content" in case the resumed download fails.
    @Test func createWithStatusCodePartialContent() throws {
        // Given
        let response = _makeResponse(statusCode: 206, headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "ETag": "1234"
        ])
        let data = try #require(ResumableData(response: response, data: _data))

        // Then
        #expect(data.data.count == 1000)
        #expect(data.validator == "1234")
    }

    // MARK: - Creation (Negative)

    @Test func createWithEmptyData() {
        // Given
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "ETag": "1234"
        ])
        let data = ResumableData(response: response, data: Data())

        // Then
        #expect(data == nil)
    }

    @Test func createWithNotHTTPResponse() {
        // Given
        let response = URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 10000, textEncodingName: nil)
        let data = ResumableData(response: response, data: _data)

        // Then
        #expect(data == nil)
    }

    @Test func createWithInvalidStatusCode() {
        // Given
        let response = _makeResponse(statusCode: 304, headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "ETag": "1234"
        ])
        let data = ResumableData(response: response, data: _data)

        // Then
        #expect(data == nil)
    }

    @Test func createWithMissingValidator() {
        // Given
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000"
        ])
        let data = ResumableData(response: response, data: _data)

        // Then
        #expect(data == nil)
    }

    @Test func createWithMissingAcceptRanges() {
        // Given
        let response = _makeResponse(headers: [
            "ETag": "1234",
            "Content-Length": "2000"
        ])
        let data = ResumableData(response: response, data: _data)

        // Then
        #expect(data == nil)
    }

    @Test func createWithAcceptRangesNone() {
        // Given
        let response = _makeResponse(headers: [
            "Accept-Ranges": "none",
            "Content-Length": "2000",
            "ETag": "1234"
        ])
        let data = ResumableData(response: response, data: _data)

        // Then
        #expect(data == nil)
    }

    @Test func createWhenFullDataIsLoaded() {
        // Given
        let response = _makeResponse(headers: [
            "Accept-Ranges": "none",
            "Content-Length": "1000",
            "ETag": "1234"
        ])
        let data = ResumableData(response: response, data: _data)

        // Then
        #expect(data == nil)
    }
}

private let _data = Data(count: 1000)

private func _makeResponse(statusCode: Int = 200, headers: [String: String]? = nil) -> HTTPURLResponse {
    return HTTPURLResponse(url: Test.url, statusCode: statusCode, httpVersion: "HTTP/1.2", headerFields: headers)!
}
