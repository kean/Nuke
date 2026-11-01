// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

/// A data loader that does what the test scripts it to do, one step per
/// request, and serves `Test.data` once it runs out of steps.
final class MockScriptedDataLoader: DataLoading, @unchecked Sendable {
    enum Step {
        /// Fails with the given error.
        case fail(any Error)
        /// Serves the given data.
        case serve(Data)
        /// Fails, and keeps the callbacks of the request for ``callbacks`` to
        /// call them after the request is over.
        case failKeepingCallbacks(any Error)
        /// Never completes, until the test tells it to with ``resumeHeldRequest()``.
        case hold
    }

    typealias Callbacks = (didReceiveData: @Sendable (Data, URLResponse) -> Void, completion: @Sendable (Error?) -> Void)

    var steps: [Step] {
        get { lock.withLock { _steps } }
        set { lock.withLock { _steps = newValue } }
    }
    /// Keeps the requests from being served until it is set to `false`.
    var isSuspended: Bool {
        get { queue.isSuspended }
        set { queue.isSuspended = newValue }
    }
    var requests: [URLRequest] { lock.withLock { _requests } }
    var requestCount: Int { requests.count }
    var cancelCount: Int { lock.withLock { _cancelCount } }
    /// The callbacks of the last `failKeepingCallbacks` step.
    var callbacks: Callbacks? { lock.withLock { _callbacks } }
    /// `true` if a `hold` step is waiting for ``resumeHeldRequest()``.
    var isHoldingRequest: Bool { lock.withLock { _held != nil } }

    private let lock = NSLock()
    private let queue = OperationQueue()
    private var _steps: [Step]
    private var _requests: [URLRequest] = []
    private var _cancelCount = 0
    private var _callbacks: Callbacks?
    private var _held: (@Sendable () -> Void)?

    init(steps: [Step] = []) {
        self._steps = steps
        queue.maxConcurrentOperationCount = 1
    }

    /// Serves `Test.data` to the request held by a `hold` step.
    func resumeHeldRequest() {
        lock.withLock { exchange(&_held, with: nil) }?()
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let step = lock.withLock {
            _requests.append(request)
            return _steps.isEmpty ? Step.serve(Test.data) : _steps.removeFirst()
        }
        let response = URLResponse(url: request.url ?? Test.url, mimeType: "jpeg", expectedContentLength: Test.data.count, textEncodingName: nil)
        queue.addOperation { [self] in
            switch step {
            case .fail(let error):
                completion(error)
            case .serve(let data):
                didReceiveData(data, response)
                completion(nil)
            case .failKeepingCallbacks(let error):
                lock.withLock { _callbacks = (didReceiveData, completion) }
                completion(error)
            case .hold:
                lock.withLock {
                    _held = {
                        didReceiveData(Test.data, response)
                        completion(nil)
                    }
                }
            }
        }
        return MockScriptedDataTask { [weak self] in
            self?.lock.withLock { self?._cancelCount += 1 }
        }
    }
}

private final class MockScriptedDataTask: Cancellable, Sendable {
    private let onCancel: @Sendable () -> Void

    init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel()
    }
}

/// A delegate that decides about the retries with the given closure.
final class MockRetryDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    /// The failures the pipeline asked about, in order.
    var contexts: [ImagePipeline.RetryContext] { lock.withLock { _contexts } }

    private let lock = NSLock()
    private var _contexts: [ImagePipeline.RetryContext] = []
    private let handler: @Sendable (ImagePipeline.RetryContext) async -> ImagePipeline.RetryDecision

    init(handler: @escaping @Sendable (ImagePipeline.RetryContext) async -> ImagePipeline.RetryDecision) {
        self.handler = handler
    }

    func retryDecision(for context: ImagePipeline.RetryContext, pipeline: ImagePipeline) async -> ImagePipeline.RetryDecision {
        lock.withLock { _contexts.append(context) }
        return await handler(context)
    }
}

extension ImagePipeline.RetryPolicy {
    /// A policy that retries right away, in the order the steps are scripted.
    static func immediate(_ maxRetryCount: Int = 2) -> Self {
        .init(maxRetryCount: maxRetryCount, backoff: .fixed(0), jitter: 0, connectivityTimeout: 0)
    }

    /// A policy that doesn't get to the retry before the end of a test.
    static var waiting: Self {
        .init(maxRetryCount: 2, backoff: .fixed(600), jitter: 0, maximumDelay: 600, connectivityTimeout: 0)
    }
}
