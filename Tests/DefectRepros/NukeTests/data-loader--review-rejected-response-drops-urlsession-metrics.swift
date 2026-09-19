// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: a download that `DataLoader` rejects in validation (any non-2xx status,
// e.g. "404 Not Found") never gets its `URLSession` metrics, so the
// diagnostics of exactly the failures worth diagnosing have none.
//
// Sources/Nuke/Loading/DataLoader.swift, `_DataLoader.urlSession(_:dataTask:
// didReceive:completionHandler:)`: when `validate` rejects the response, the
// loader removes the handler and calls `handler.completion(error, nil)` right
// away, with `nil` metrics. `URLSession` collects the task's metrics only
// after that (`didFinishCollecting` follows the `.cancel` disposition), and by
// then `didFinishCollecting` finds no handler, so the metrics are dropped.
//
// `ImagePipeline.Diagnostics.Stage.urlSessionMetrics` documents: "`nil` if the
// data loader isn't a ``DataLoader``, or if the download hadn't completed when
// the record was captured." Here the loader is a `DataLoader` and the download
// has completed (the task failed with `.dataLoadingFailed`), yet the metrics
// are `nil`. `ImageTask.Metrics.urlSessionMetrics` (and so `wireBytes`,
// redirects, timing) is `nil` for every 4xx/5xx image. (`Stage.statusCode` is
// `nil` too: it's only recorded when the first chunk of data arrives, and a
// rejected response delivers none.)
//
// Expected: the download stage of the failed task has `urlSessionMetrics`,
//           the way it does for a successful download and for a download
//           that fails with a network error.
// Actual:   `urlSessionMetrics == nil`.

@Suite(.timeLimit(.minutes(1)))
struct RejectedResponseURLSessionMetricsBugTests {
    @Test func rejectedResponseHasURLSessionMetrics() async throws {
        try await expectURLSessionMetricsForFailedDownload(of: URL(string: "failing://diagnostics/404.jpeg")!)
    }

    /// Control: a download that fails with a network error mid-body has the
    /// metrics. (Passes.)
    @Test func networkFailureHasURLSessionMetrics() async throws {
        try await expectURLSessionMetricsForFailedDownload(of: URL(string: "failing://diagnostics/lost.jpeg")!)
    }

    private func expectURLSessionMetricsForFailedDownload(of url: URL) async throws {
        // GIVEN a pipeline on `DataLoader` with diagnostics on
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [_FailingURLProtocol.self]
        let pipeline = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: configuration)
            $0.imageCache = nil
            $0.dataCache = nil
            $0.isDiagnosticsEnabled = true
        }

        // WHEN
        let task = pipeline.imageTask(with: url)
        do {
            _ = try await task.response
            Issue.record("Expected the load to fail")
        } catch {
            guard case .dataLoadingFailed = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }

        // THEN the completed download carries what the session measured
        let metrics = try #require(task.metrics)
        let download = try #require(metrics.jobs.last?.stages.first { $0.kind == .download })
        #expect(download.urlSessionTaskID != nil)
        #expect(download.urlSessionMetrics != nil)
        #expect(metrics.urlSessionMetrics != nil)
    }
}

/// "404.jpeg" answers "404 Not Found"; "lost.jpeg" answers "200 OK" and
/// drops the connection after a part of the body.
private final class _FailingURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "failing"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let isNotFound = request.url?.lastPathComponent == "404.jpeg"
        let response = HTTPURLResponse(url: request.url!, statusCode: isNotFound ? 404 : 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "100"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 1, count: 50))
        if isNotFound {
            client?.urlProtocolDidFinishLoading(self)
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        }
    }

    override func stopLoading() {}
}
