// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: `DataLoader.delegate` is written without synchronization while the
// session's delegate queue reads it.
//
// Sources/Nuke/Loading/DataLoader.swift:
//
//     public var delegate: URLSessionDelegate? {
//         didSet { impl.delegate = delegate }
//     }
//
// `_DataLoader.delegate` is a plain stored `var` that every `URLSession`
// callback reads on the delegate queue (`(delegate as? ...)?.urlSession?(...)`).
// Setting `DataLoader.delegate` from any other thread while a load is in flight
// — e.g. turning on Pulse logging from a debug menu with
// `(ImagePipeline.shared.configuration.dataLoader as? DataLoader)?.delegate =
// URLSessionProxyDelegate()`, the documented snippet — races with those reads.
// A racing read of a strong class reference can observe it while it's being
// released (use-after-free). `DataLoader` is `@unchecked Sendable`, so the
// compiler doesn't flag it. The same pattern on `prefersIncrementalDelivery`
// was fixed as a data race in #928 (CHANGELOG: "Fix a data race on
// `DataLoader/prefersIncrementalDelivery`") by moving it into a lock.
//
// `urlSession(_:didCreateTask:)` makes it worse: `URLSession` calls it
// synchronously on the thread that creates the task (inside
// `session.dataTask(with:)`), i.e. on whatever thread calls `loadData`.
//
// Expected: the test finishes, and no data race is reported.
// Actual:   without any sanitizer the test process crashes ("Crash: xctest";
//           a standalone binary doing the same crashes every run with
//           EXC_BAD_ACCESS / SIGSEGV in `objc_retain` called from
//           `_DataLoader.urlSession(_:didCreateTask:)` ←
//           `DataLoader.loadData(with:collectsMetrics:didReceiveData:completion:)`).
//           With `-enableThreadSanitizer YES`: "ThreadSanitizer: data race" —
//           read in `_DataLoader.urlSession(_:didCreateTask:)`, previous write
//           in `DataLoader.delegate.didset`.

@Suite(.serialized, .timeLimit(.minutes(2)))
struct DataLoaderDelegateRaceBugTests {
    @Test func delegateIsReplacedWhileLoadingData() async throws {
        // GIVEN
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [_RaceProtocol.self]
        let loader = DataLoader(configuration: configuration)

        let writer = Task.detached {
            while !Task.isCancelled {
                loader.delegate = _RaceDelegate()
                await Task.yield()
            }
        }

        // WHEN loading data while the delegate is being replaced
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    let url = URL(string: "race://test/\(index).jpeg")!
                    for try await _ in loader.loadData(with: URLRequest(url: url)) {}
                }
            }
            try await group.waitForAll()
        }

        // THEN no data races are reported
        writer.cancel()
        await writer.value
    }
}

private final class _RaceDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {}
}

private final class _RaceProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme == "race" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "1"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("x".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
