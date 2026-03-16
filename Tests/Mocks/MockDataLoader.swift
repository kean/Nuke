// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

private let data: Data = Test.data(name: "fixture", extension: "jpeg")

class MockDataLoader: DataLoading, @unchecked Sendable {
    static let DidStartTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidStartTask")
    static let DidCancelTask = Notification.Name("com.github.kean.Nuke.Tests.MockDataLoader.DidCancelTask")

    @Mutex var createdTaskCount = 0
    var results = [URL: Result<(Data, URLResponse), NSError>]()
    let queue = Gate()
    var isSuspended: Bool {
        get { queue.isSuspended }
        set { queue.isSuspended = newValue }
    }

    // - warning: these get executed in a background now
    func loadData(with request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse) {
        let response: URLResponse
        if let result = results[request.url!] {
            switch result {
            case let .success(val): response = val.1
            case .failure: response = URLResponse(url: request.url ?? Test.url, mimeType: nil, expectedContentLength: -1, textEncodingName: nil)
            }
        } else {
            response = URLResponse(url: request.url ?? Test.url, mimeType: "jpeg", expectedContentLength: 22789, textEncodingName: nil)
        }

        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.onTermination = { @Sendable termination in
                if case .cancelled = termination {
                    NotificationCenter.default.post(name: MockDataLoader.DidCancelTask, object: self)
                }
            }
            Task {
                await self.queue.wait()
                if let result = self.results[request.url!] {
                    switch result {
                    case let .success(val):
                        let data = val.0
                        if !data.isEmpty {
                            continuation.yield(data.prefix(data.count / 2))
                            continuation.yield(data.suffix(data.count / 2))
                        }
                        continuation.finish()
                    case let .failure(err):
                        continuation.finish(throwing: err)
                    }
                } else {
                    continuation.yield(data)
                    continuation.finish()
                }
            }
        }

        if Task.isCancelled {
            NotificationCenter.default.post(name: MockDataLoader.DidCancelTask, object: self)
            throw CancellationError()
        }

        // - warning: Important so it runs atomically
        $createdTaskCount.withLock { $0 = $0 + 1 }
        NotificationCenter.default.post(name: MockDataLoader.DidStartTask, object: self)

        return (stream, response)
    }
}

/// A Swift-concurrency-native suspension gate. Replaces OperationQueue to avoid
/// starving GCD's thread pool when many concurrent async tests are running.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var _isSuspended = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    var isSuspended: Bool {
        get { lock.withLock { _isSuspended } }
        set {
            let toResume = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                _isSuspended = newValue
                guard !newValue else { return [] }
                defer { waiters.removeAll() }
                return Array(waiters.values)
            }
            for c in toResume { c.resume() }
        }
    }

    func wait() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    if _isSuspended {
                        waiters[id] = continuation
                    } else {
                        continuation.resume()
                    }
                }
            }
        } onCancel: {
            lock.withLock { waiters.removeValue(forKey: id) }?.resume()
        }
    }
}
