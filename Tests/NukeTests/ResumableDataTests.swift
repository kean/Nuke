// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// Test ResumableData directly to make sure it makes the right decisions based
// on HTTP flows.
@Suite(.timeLimit(.minutes(5)))
struct ResumableDataTests {
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

    @Test func resumingRequestUsesLastModifiedWhenNoETag() {
        // GIVEN resumable data validated by Last-Modified (no ETag)
        let lastModified = "Wed, 21 Oct 2015 07:28:00 GMT"
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "Last-Modified": lastModified
        ])
        let data = ResumableData(response: response, data: _data)!
        var request = URLRequest(url: Test.url)
        data.resume(request: &request)

        // THEN Range header is correct and If-Range contains the Last-Modified value
        #expect(request.allHTTPHeaderFields?["Range"] == "bytes=1000-")
        #expect(request.allHTTPHeaderFields?["If-Range"] == lastModified)
    }

    @Test func checkingResumedResponse() {
        #expect(ResumableData.isResumedResponse(_makeResponse(statusCode: 206)))

        // Need to load new data
        #expect(!ResumableData.isResumedResponse(_makeResponse(statusCode: 200)))

        #expect(!ResumableData.isResumedResponse(_makeResponse(statusCode: 404)))
    }

    // MARK: - Creation (Positive)

    @Test func createWithETag() {
        // Given
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "ETag": "1234"
        ])
        let data = ResumableData(response: response, data: _data)

        // Then
        #expect(data != nil)
        #expect(data?.data.count == 1000)
        #expect(data?.validator == "1234")
    }

    @Test func createWithETagSpelledIncorrectly() {
        // Given
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "Etag": "1234"
        ])
        let data = ResumableData(response: response, data: _data)

        // Then
        #expect(data != nil)
        #expect(data?.data.count == 1000)
        #expect(data?.validator == "1234")
    }

    @Test func createWithLastModified() {
        // Given
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "Last-Modified": "Wed, 21 Oct 2015 07:28:00 GMT"
        ])
        let data = ResumableData(response: response, data: _data)

        // Then
        #expect(data != nil)
        #expect(data?.data.count == 1000)
        #expect(data?.validator == "Wed, 21 Oct 2015 07:28:00 GMT")
    }

    @Test func createWithBothValidators() {
        // Given
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "ETag": "1234",
            "Content-Length": "2000",
            "Last-Modified": "Wed, 21 Oct 2015 07:28:00 GMT"
        ])
        let data = ResumableData(response: response, data: _data)

        // Then
        #expect(data != nil)
        #expect(data?.data.count == 1000)
        #expect(data?.validator == "1234")
    }

    // We should store resumable data not just for status code "200 OK", but also
    // for "206 Partial Content" in case the resumed download fails.
    @Test func createWithStatusCodePartialContent() {
        // Given
        let response = _makeResponse(statusCode: 206, headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "ETag": "1234"
        ])
        let data = ResumableData(response: response, data: _data)

        // Then
        #expect(data != nil)
        #expect(data?.data.count == 1000)
        #expect(data?.validator == "1234")
    }

    // The "Content-Length" of a "206 Partial Content" response covers only the
    // remaining bytes, while the data also includes the resumed ones.
    @Test func createWithStatusCodePartialContentIncludingResumedData() {
        // Given 1500 of 2000 bytes, 1000 of which came from the previous attempt
        let response = _makeResponse(statusCode: 206, headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "1000",
            "ETag": "1234"
        ])
        let data = ResumableData(response: response, data: Data(count: 1500), resumedDataCount: 1000)

        // Then
        #expect(data?.data.count == 1500)
    }

    @Test func createWithStatusCodePartialContentWhenDownloadIsCompleteReturnsNil() {
        // Given all 2000 bytes, 1000 of which came from the previous attempt
        let response = _makeResponse(statusCode: 206, headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "1000",
            "ETag": "1234"
        ])
        let data = ResumableData(response: response, data: Data(count: 2000), resumedDataCount: 1000)

        // Then
        #expect(data == nil)
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

    @Test func createWhenDownloadIsCompleteReturnsNil() {
        // GIVEN data whose length equals the Content-Length (download is complete)
        let completeData = Data(count: 2000)
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "ETag": "1234"
        ])

        // WHEN trying to create resumable data from a fully-downloaded response
        let data = ResumableData(response: response, data: completeData)

        // THEN no resumable data is created — there is nothing to resume
        #expect(data == nil)
    }

    @Test func createWhenDataExceedsContentLengthReturnsNil() {
        // GIVEN data that exceeds the declared Content-Length (e.g. due to rounding)
        let oversizedData = Data(count: 2001)
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "ETag": "xyz"
        ])

        let data = ResumableData(response: response, data: oversizedData)

        #expect(data == nil)
    }

    /// Without a "Content-Length" there is no telling whether the download
    /// is incomplete (e.g. "Transfer-Encoding: chunked").
    @Test func createWithoutContentLengthReturnsNil() {
        // Given
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "ETag": "1234"
        ])

        // Then
        #expect(response.expectedContentLength == -1)
        #expect(ResumableData(response: response, data: _data) == nil)
    }

    @Test(arguments: [201, 203, 204, 226])
    func createWithOtherSuccessfulStatusCodeReturnsNil(statusCode: Int) {
        // Given
        let response = _makeResponse(statusCode: statusCode, headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "ETag": "1234"
        ])

        // Then
        #expect(ResumableData(response: response, data: _data) == nil)
    }

    // MARK: - Header Formats

    /// HTTP/2 servers send header names in lowercase.
    @Test func createWithLowercaseHeaderNames() throws {
        // Given
        let response = _makeResponse(headers: [
            "accept-ranges": "bytes",
            "content-length": "2000",
            "etag": "\"abc\""
        ])

        // When
        let data = try #require(ResumableData(response: response, data: _data))

        // Then the quoted entity tag is sent back verbatim
        var request = URLRequest(url: Test.url)
        data.resume(request: &request)
        #expect(request.value(forHTTPHeaderField: "If-Range") == "\"abc\"")
    }

    @Test func createWithLowercaseLastModified() throws {
        // Given
        let response = _makeResponse(headers: [
            "accept-ranges": "bytes",
            "content-length": "2000",
            "last-modified": "Wed, 21 Oct 2015 07:28:00 GMT"
        ])

        // When
        let data = try #require(ResumableData(response: response, data: _data))

        // Then
        #expect(data.validator == "Wed, 21 Oct 2015 07:28:00 GMT")
    }

    /// Range units are case-insensitive (RFC 9110).
    @Test func createWithUppercaseRangeUnit() {
        // Given
        let response = _makeResponse(headers: [
            "Accept-Ranges": "BYTES",
            "Content-Length": "2000",
            "ETag": "1234"
        ])

        // Then
        #expect(ResumableData(response: response, data: _data) != nil)
    }

    // MARK: - Resuming

    @Test func resumingRequestKeepsOtherHeadersAndReplacesRange() throws {
        // Given a request that already asks for a range
        let response = _makeResponse(headers: [
            "Accept-Ranges": "bytes",
            "Content-Length": "2000",
            "ETag": "1234"
        ])
        let data = try #require(ResumableData(response: response, data: _data))
        var request = URLRequest(url: Test.url)
        request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
        request.setValue("bytes=0-99", forHTTPHeaderField: "Range")

        // When
        data.resume(request: &request)

        // Then
        #expect(request.value(forHTTPHeaderField: "Range") == "bytes=1000-")
        #expect(request.value(forHTTPHeaderField: "If-Range") == "1234")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    @Test func nonHTTPResponseIsNotResumed() {
        let response = URLResponse(url: Test.url, mimeType: "image/jpeg", expectedContentLength: 2000, textEncodingName: nil)
        #expect(!ResumableData.isResumedResponse(response))
    }
}

/// Uses its own ``ResumableDataStorage`` instead of the shared one, which every
/// pipeline in the test process registers with, so that its lifecycle can be
/// observed, and so that removing all responses doesn't take the data from
/// under the suites running in parallel.
@ImagePipelineActor
@Suite(.timeLimit(.minutes(5)))
struct ResumableDataStorageTests {
    private let storage = ResumableDataStorage()
    private let pipeline = ImagePipeline { $0.dataLoader = MockDataLoader() }
    private let request = ImageRequest(url: Test.url)

    @Test func storingBeforeAnyPipelineRegistersIsIgnored() {
        // When
        storage.storeResumableData(_makeResumableData(), for: request, pipeline: pipeline)
        storage.register(pipeline.id)

        // Then
        #expect(storage.removeResumableData(for: request, pipeline: pipeline) == nil)
    }

    @Test func unregisteringTheLastPipelineDropsTheData() {
        // Given
        storage.register(pipeline.id)
        storage.storeResumableData(_makeResumableData(), for: request, pipeline: pipeline)

        // When
        storage.unregister(pipeline.id)

        // Then
        #expect(storage.removeResumableData(for: request, pipeline: pipeline) == nil)
    }

    @Test func dataIsKeptWhileAnyPipelineIsRegistered() {
        // Given
        let other = ImagePipeline { $0.dataLoader = MockDataLoader() }
        storage.register(pipeline.id)
        storage.register(other.id)
        storage.storeResumableData(_makeResumableData(), for: request, pipeline: pipeline)

        // When
        storage.unregister(other.id)

        // Then
        #expect(storage.removeResumableData(for: request, pipeline: pipeline) != nil)
    }

    @Test func registeringThePipelineTwiceNeedsOneUnregister() {
        // Given
        storage.register(pipeline.id)
        storage.register(pipeline.id)
        storage.storeResumableData(_makeResumableData(), for: request, pipeline: pipeline)

        // When
        storage.unregister(pipeline.id)

        // Then
        #expect(storage.removeResumableData(for: request, pipeline: pipeline) == nil)
    }

    @Test func dataIsScopedToThePipeline() {
        // Given
        let other = ImagePipeline { $0.dataLoader = MockDataLoader() }
        storage.register(pipeline.id)
        storage.register(other.id)

        // When
        storage.storeResumableData(_makeResumableData(), for: request, pipeline: pipeline)

        // Then
        #expect(storage.removeResumableData(for: request, pipeline: other) == nil)
        #expect(storage.removeResumableData(for: request, pipeline: pipeline) != nil)
    }

    @Test func dataIsScopedToTheImage() {
        // Given
        storage.register(pipeline.id)

        // When
        storage.storeResumableData(_makeResumableData(), for: request, pipeline: pipeline)

        // Then
        let other = ImageRequest(url: URL(string: "https://example.com/other.jpeg"))
        #expect(storage.removeResumableData(for: other, pipeline: pipeline) == nil)
        #expect(storage.removeResumableData(for: request, pipeline: pipeline) != nil)
    }

    @Test func requestWithoutURLIsIgnored() {
        // Given
        storage.register(pipeline.id)
        let request = ImageRequest(url: nil)

        // When
        storage.storeResumableData(_makeResumableData(), for: request, pipeline: pipeline)

        // Then
        #expect(storage.removeResumableData(for: request, pipeline: pipeline) == nil)
    }

    @Test func storingAgainReplacesThePreviousData() {
        // Given
        storage.register(pipeline.id)
        storage.storeResumableData(_makeResumableData(count: 100, validator: "v1"), for: request, pipeline: pipeline)

        // When
        storage.storeResumableData(_makeResumableData(count: 200, validator: "v2"), for: request, pipeline: pipeline)

        // Then
        let stored = storage.removeResumableData(for: request, pipeline: pipeline)
        #expect(stored?.validator == "v2")
        #expect(stored?.data.count == 200)
        #expect(storage.removeResumableData(for: request, pipeline: pipeline) == nil)
    }

    @Test func oldestDataIsEvictedAfter100Entries() {
        // Given
        storage.register(pipeline.id)
        let requests = (0...100).map { ImageRequest(url: URL(string: "https://example.com/\($0).jpeg")) }

        // When
        for request in requests {
            storage.storeResumableData(_makeResumableData(), for: request, pipeline: pipeline)
        }

        // Then
        #expect(storage.removeResumableData(for: requests[0], pipeline: pipeline) == nil)
        #expect(storage.removeResumableData(for: requests[1], pipeline: pipeline) != nil)
        #expect(storage.removeResumableData(for: requests[100], pipeline: pipeline) != nil)
    }

    @Test func removingAllResponsesDropsTheData() {
        // Given
        storage.register(pipeline.id)
        storage.storeResumableData(_makeResumableData(), for: request, pipeline: pipeline)

        // When
        storage.removeAllResponses()

        // Then
        #expect(storage.removeResumableData(for: request, pipeline: pipeline) == nil)
    }

    @Test func removingAllResponsesKeepsTheStorageUsable() {
        // Given
        storage.register(pipeline.id)
        storage.storeResumableData(_makeResumableData(), for: request, pipeline: pipeline)

        // When
        storage.removeAllResponses()
        storage.storeResumableData(_makeResumableData(validator: "v2"), for: request, pipeline: pipeline)

        // Then
        #expect(storage.removeResumableData(for: request, pipeline: pipeline)?.validator == "v2")
    }
}

private let _data = Data(count: 1000)

private func _makeResumableData(count: Int = 1000, validator: String = "1234") -> ResumableData {
    let response = _makeResponse(headers: [
        "Accept-Ranges": "bytes",
        "Content-Length": String(count * 2),
        "ETag": validator
    ])
    return ResumableData(response: response, data: Data(count: count))!
}

private func _makeResponse(statusCode: Int = 200, headers: [String: String]? = nil) -> HTTPURLResponse {
    return HTTPURLResponse(url: Test.url, statusCode: statusCode, httpVersion: "HTTP/1.2", headerFields: headers)!
}
