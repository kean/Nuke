// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

private let _data = Data(count: 1000)

private func _makeResponse(statusCode: Int = 200, headers: [String: String]? = nil) -> HTTPURLResponse {
    return HTTPURLResponse(url: defaultURL, statusCode: statusCode, httpVersion: "HTTP/1.2", headerFields: headers)!
}

class ImagePipelineResumableDataTests: XCTestCase {
    private var dataLoader: _MockResumableDataLoader!
    private var pipeline: ImagePipeline!

    override func setUp() {
        dataLoader = _MockResumableDataLoader()
        ResumableData._cache.removeAll()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // Make sure that ResumableData works correctly in integration with ImagePipeline
    func testRangeSupported() {
        expect { fulfil in
            let _ = pipeline.loadImage(with: defaultURL) { _, error in
                XCTAssertNotNil(error)
                fulfil()
            }
        }
        wait()

        expect { fulfil in
            pipeline.didFinishCollectingMetrics = { _, metrics in
                // Test that the metrics are collected correctly.
                XCTAssertEqual(metrics.session!.wasResumed, true)
                XCTAssertTrue(metrics.session!.resumedDataCount! > 0)
                XCTAssertEqual(metrics.session!.totalDownloadedDataCount, self.dataLoader.data.count)
                fulfil()
            }
        }

        expect { fulfil in
            pipeline.loadImage(with: defaultURL) { response, _ in
                XCTAssertNotNil(response)
                fulfil()
            }
        }
        wait()
    }
}

// Test ResumableData directly to make sure it makes the right decisions based
// on HTTP flows.
class ResumableDataTests: XCTestCase {
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

    // MARK: - Creation (Positive)

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

    // MARK: - Creation (Negative)

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

private class _MockResumableDataLoader: DataLoading {
    private let queue = DispatchQueue(label: "_MockResumableDataLoader")

    let data: Data = Test.data(name: "fixture", extension: "jpeg")
    let eTag: String = "img_01"

    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> Cancellable {
        let headers = request.allHTTPHeaderFields

        // Check if the client already has some resumable data available.
        if let range = headers?["Range"], let validator = headers?["If-Range"] {
            let offset = _groups(regex: "bytes=(\\d*)-", in: range)[0]
            XCTAssertNotNil(offset)

            XCTAssertEqual(validator, eTag)
            guard validator == eTag else { // Expected ETag
                XCTFail()
                return _Task()
            }

            // Ideally the server must also respond with  "Content-Range" and
            // "Content-Length" but we don't use those fields

            let response = HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: "HTTP/1.2", headerFields: [:])!
            // Send remaining data in chunks
            var chunks = Array(_createChunks(for: data[Int(offset)!...], size: data.count / 10))

            // Send half of chunks away.
            while let chunk = chunks.first {
                chunks.removeFirst()
                queue.async {
                    didReceiveData(chunk, response)
                }
            }
            queue.async {
                completion(nil)
            }
        } else {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.2", headerFields: [
                "Accept-Ranges": "bytes",
                "ETag": eTag
                ])!

            var chunks = Array(_createChunks(for: data, size: data.count / 10))
            chunks.removeLast(chunks.count / 2)

            while let chunk = chunks.first {
                chunks.removeFirst()
                queue.async {
                    didReceiveData(chunk, response)
                }
            }
            queue.async {
                completion(NSError(domain: NSURLErrorDomain, code: URLError.networkConnectionLost.rawValue, userInfo: [:]))
            }
        }

        return _Task()
    }

    private class _Task: Cancellable {
        func cancel() { }
    }
}
