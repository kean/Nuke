// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

// MARK: - URLProtocol Mock

/// A custom URL scheme–based mock that intercepts requests to `mock://` URLs.
/// Each test registers per-URL handlers before loading.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    /// Per-URL request handler: receives the request, calls methods on
    /// the protocol client (`startLoading` bridge), and signals completion.
    nonisolated(unsafe) static var handlers = [URL: Handler]()

    struct Handler {
        /// Called on the URL loading thread. Use `client` to send response, data, and completion.
        let handle: (_ request: URLRequest, _ client: any URLProtocolClient, _ protocol: URLProtocol) -> Void
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "mock"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let handler = MockURLProtocol.handlers[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        handler.handle(request, client!, self)
    }

    override func stopLoading() {}
}

// MARK: - Helpers

/// Creates a `DataLoader` configured to use `MockURLProtocol`.
func makeDataLoader(
    validate: @Sendable @escaping (URLResponse) -> Error? = DataLoader.validate
) -> DataLoader {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return DataLoader(configuration: config, validate: validate)
}

func mockURL(_ path: String = "image.jpg") -> URL {
    URL(string: "mock://test/\(path)")!
}

/// Registers a handler that responds with the given status code, headers, and
/// data chunks (each chunk delivered as a separate `didLoad` call).
func registerMock(
    url: URL,
    statusCode: Int = 200,
    headers: [String: String]? = nil,
    chunks: [Data]
) {
    var allHeaders = headers ?? [:]
    let totalSize = chunks.reduce(0) { $0 + $1.count }
    if allHeaders["Content-Length"] == nil {
        allHeaders["Content-Length"] = "\(totalSize)"
    }
    MockURLProtocol.handlers[url] = .init { request, client, proto in
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: allHeaders
        )!
        client.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in chunks {
            client.urlProtocol(proto, didLoad: chunk)
        }
        client.urlProtocolDidFinishLoading(proto)
    }
}

/// Registers a handler that fails with the given error (before sending a response).
func registerMockError(url: URL, error: URLError) {
    MockURLProtocol.handlers[url] = .init { _, client, proto in
        client.urlProtocol(proto, didFailWithError: error)
    }
}

/// Registers a handler that sends a response, some data, then fails mid-stream.
func registerMockPartialFailure(
    url: URL,
    statusCode: Int = 200,
    data: Data,
    error: URLError
) {
    MockURLProtocol.handlers[url] = .init { _, client, proto in
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(data.count * 2)"] // Pretend more data expected
        )!
        client.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(proto, didLoad: data)
        client.urlProtocol(proto, didFailWithError: error)
    }
}
