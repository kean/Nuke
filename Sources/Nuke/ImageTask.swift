// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// A task performed by the ``ImagePipeline``.
///
/// The pipeline maintains a strong reference to the task until it completes.
/// You do not need to maintain your own reference unless it is useful for your app.
///
/// ## Thread Safety
///
/// All public properties can be safely accessed from any thread. The task's
/// state, priority, and cancellation status provide immediate, thread-safe snapshots.
public final class ImageTask: Hashable, JobSubscriber, Sendable {
    /// An identifier that uniquely identifies the task within a given pipeline.
    public let taskId: Int64

    /// The original request used to create this task.
    public let request: ImageRequest

    // TODO: fix this being on ImagePipelineActor right now
    /// The task priority. Can be updated dynamically, even while the task is running.
    public var priority: ImageRequest.Priority {
        get { nonisolatedState.withLock(\.priority) }
        set { setPriority(newValue) }
    }

    /// A snapshot of the current download progress.
    ///
    /// - note: The `total` value is zero when the resource size is unknown or
    /// the server doesn't provide a `Content-Length` header. The `fraction`
    /// property handles this by returning 0.
    ///
    /// - seealso: ``ImageTask/progress`` for receiving progress updates.
    public var currentProgress: Progress {
        nonisolatedState.withLock(\.progress)
    }

    /// The current state of the task.
    ///
    /// - seealso:
    ///   - ``isCancelled`` to check if cancellation was initiated
    ///   - ``events`` to observe state transitions in real-time
    public var state: State {
        nonisolatedState.withLock(\.state)
    }

    /// Returns `true` if the task was cancelled.
    ///
    /// - seealso:
    ///   - ``cancel()`` to cancel the task
    ///   - ``state`` for the final outcome
    ///   - ``ImageTask/Error/cancelled`` error case
    public var isCancelled: Bool {
        nonisolatedState.withLock(\.isCancelled)
    }

    var isTerminated: Bool {
        guard case .running = state else { return true }
        return false
    }

    // MARK: - Async/Await

    /// Returns the response image.
    public var image: PlatformImage {
        get async throws(ImageTask.Error) {
            try await response.image
        }
    }

    /// Returns the image response.
    public var response: ImageResponse {
        get async throws(ImageTask.Error) {
            do {
                return try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: {
                    cancel()
                }
            } catch {
                throw error as! ImageTask.Error
            }
        }
    }

    /// A stream of progress updates during the download.
    public var progress: AsyncCompactMapSequence<AsyncStream<Event>, Progress> {
        events.compactMap {
            if case .progress(let value) = $0 { return value }
            return nil
        }
    }

    /// The stream of image previews generated for images that support
    /// progressive decoding.
    ///
    /// Progressive decoding allows you to display low-resolution previews
    /// while the full image is still downloading, improving perceived performance.
    ///
    /// - seealso: ``ImagePipeline/Configuration-swift.struct/isProgressiveDecodingEnabled``
    public var previews: AsyncCompactMapSequence<AsyncStream<Event>, ImageResponse> {
        events.compactMap {
            if case .preview(let value) = $0 { return value }
            return nil
        }
    }

    /// A stream of events during task execution.
    ///
    /// Events are yielded in the following order:
    /// 1. Zero or more `.progress` events as data downloads
    /// 2. Zero or more `.preview` events for progressive images (if enabled)
    /// 3. Exactly one `.finished` event with the final result
    ///
    /// The stream completes after the `.finished` event is sent.
    ///
    /// ## Example
    /// ```swift
    /// for await event in task.events {
    ///     switch event {
    ///     case .progress(let progress):
    ///         progressBar.progress = progress.fraction
    ///     case .preview(let response):
    ///         imageView.image = response.image // Show progressive scan
    ///     case .finished(.success(let response)):
    ///         imageView.image = response.image // Show final image
    ///     case .finished(.failure(let error)):
    ///         handleError(error)
    ///     }
    /// }
    /// ```
    public var events: AsyncStream<Event> {
        AsyncStream { continuation in
            Task { @ImagePipelineActor [weak self] in
                guard let self, !self.isTerminated else {
                    return continuation.finish()
                }
                self._state.streamContinuations.append(continuation)
            }
        }
    }

    private let nonisolatedState: Mutex<NonisolatedState>

    /// The state that can be accessed synchronously by the users of the task.
    private struct NonisolatedState {
        var isCancelled = false
        var state: ImageTask.State = .running
        var priority: ImageRequest.Priority
        var progress = ImageTask.Progress(completed: 0, total: 0)
    }

    @ImagePipelineActor
    private var _state = IsolatedState()

    /// The part of the task that manages background jobs.
    @ImagePipelineActor
    private struct IsolatedState {
        var pipeline: ImagePipeline?
        var subscription: JobSubscription?
        var continuation: UnsafeContinuation<ImageResponse, Swift.Error>?
        var streamContinuations = ContiguousArray<AsyncStream<ImageTask.Event>.Continuation>()
    }

    let isDataTask: Bool
    private nonisolated(unsafe) var task: Task<ImageResponse, Swift.Error>!
    private let onEvent: (@ImagePipelineActor @Sendable (Event, ImageTask) -> Void)?

    init(taskId: Int64, request: ImageRequest, isDataTask: Bool, pipeline: ImagePipeline, onEvent: (@ImagePipelineActor @Sendable (Event, ImageTask) -> Void)?) {
        self.taskId = taskId
        self.request = request
        self.nonisolatedState = Mutex(NonisolatedState(priority: request.priority))
        self.isDataTask = isDataTask
        self._state.pipeline = pipeline
        self.onEvent = onEvent
        self.task = Task { @ImagePipelineActor in
            try await perform()
        }
    }

    @ImagePipelineActor
    private func perform() async throws -> ImageResponse {
        // In case the task gets cancelled immediately after creation.
        guard !isCancelled, !isTerminated, let pipeline = _state.pipeline else {
            throw ImageTask.Error.cancelled
        }
        return try await withUnsafeThrowingContinuation { continuation in
            _state.continuation = continuation
            if let subscription = pipeline.perform(self) {
                _state.subscription = subscription
            } else {
                process(.finished(.failure(.pipelineInvalidated)))
            }
        }
    }

    /// Cancels the task.
    ///
    /// The ``isCancelled`` property is set to `true` immediately. The pipeline
    /// then asynchronously attempts to stop the underlying work unless an equivalent
    /// task is running or the request has already completed.
    ///
    /// Calling this method multiple times has no effect.
    ///
    /// - note: Cancellation does not guarantee the task will stop. The task may
    /// complete successfully or fail if the work finishes before cancellation is processed.
    public func cancel() {
        let shouldCancel = nonisolatedState.withLock {
            guard !$0.isCancelled else { return false }
            $0.isCancelled = true
            return true
        }
        guard shouldCancel else { return }

        Task { @ImagePipelineActor in
            _cancel()
        }
    }

    private func setPriority(_ newValue: ImageRequest.Priority) {
        let shouldChangePriority = nonisolatedState.withLock {
            guard $0.priority != newValue else { return false }
            $0.priority = newValue
            return !$0.isCancelled
        }
        guard shouldChangePriority else { return }

        Task { @ImagePipelineActor in
            _state.subscription?.didChangePriority(newValue)
        }
    }

    // MARK: Internals

    /// Gets called when the task is cancelled either by the user or by an
    /// external event such as session invalidation.
    @ImagePipelineActor
    func _cancel() {
        process(.finished(.failure(.cancelled)))
    }

    /// - warning: The task needs to be fully wired (`_continuation` present)
    /// before it can start sending the events.
    @ImagePipelineActor
    private func process(_ event: Event) {
        guard !isTerminated else { return }

        let state = _state // Important to avoid cleanup from affecting it

        for continuation in state.streamContinuations {
            continuation.yield(event)
        }

        switch event {
        case .finished(let result):
            if case .failure(.cancelled) = result {
                state.subscription?.unsubscribe()
            }
            complete(with: result)
        case .progress(let progress):
            nonisolatedState.withLock { $0.progress = progress }
        default:
            break
        }

        onEvent?(event, self)
        state.pipeline?.imageTask(self, didProcessEvent: event)
    }

    @ImagePipelineActor
    private func complete(with result: Result<ImageResponse, ImageTask.Error>) {
        nonisolatedState.withLock { $0.state = .finished(result) }

        _state.pipeline = nil
        _state.subscription = nil

        for continuation in _state.streamContinuations {
            continuation.finish()
        }
        _state.streamContinuations.removeAll()

        _state.continuation?.resume(with: result)
        _state.continuation = nil
    }

    // MARK: JobSubscriber

    @ImagePipelineActor
    func receive(_ event: Job<ImageResponse>.Event) {
        switch event {
        case let .value(response, isCompleted):
            if isCompleted {
                process(.finished(.success(response)))
            } else {
                process(.preview(response))
            }
        case let .progress(value):
            process(.progress(value))
        case let .error(error):
            process(.finished(.failure(error)))
        }
    }

    @ImagePipelineActor
    func addSubscribedTasks(to output: inout [ImageTask]) {
        output.append(self)
    }

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self).hashValue)
    }

    public static func == (lhs: ImageTask, rhs: ImageTask) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

extension ImageTask {
    /// The download progress.
    public struct Progress: Hashable, Sendable {
        /// The number of bytes that the task has received.
        public let completed: Int64
        /// A best-guess upper bound on the number of bytes of the resource.
        public let total: Int64

        /// Returns the fraction of the completion.
        public var fraction: Float {
            guard total > 0 else { return 0 }
            return min(1, Float(completed) / Float(total))
        }

        /// Initializes progress with the given status.
        public init(completed: Int64, total: Int64) {
            (self.completed, self.total) = (completed, total)
        }
    }

    /// The state of the image task.
    ///
    /// Tasks always begin in the `.running` state and transition to `.finished`
    /// exactly once when the request completes, fails, or is cancelled.
    ///
    /// - note: Cancellation (``ImageTask/cancel()``) doesn't immediately change
    /// the state. The task transitions to `.finished` with a ``.cancelled`` error
    /// when cancellation is processed by the pipeline.
    public enum State: Sendable {
        /// The task is currently running.
        case running
        /// The task has completed.
        case finished(Result<ImageResponse, ImageTask.Error>)
    }

    /// An event produced during the runtime of the task.
    public enum Event: Sendable {
        /// The download progress was updated.
        case progress(Progress)
        /// The pipeline generated a progressive scan of the image.
        case preview(ImageResponse)
        /// The task finished with the given result.
        ///
        /// - note: If the task was cancelled, the result will contain the
        /// respective error: ``ImageTask/Error/cancelled``.
        case finished(Result<ImageResponse, ImageTask.Error>)
    }

    /// Represents all possible image task errors.
    public enum Error: Swift.Error, CustomStringConvertible, Sendable {
        /// The task got cancelled.
        ///
        /// - warning: This error case is used only for Async/Await APIs. The
        /// completion-based APIs don't report cancellation error for backward
        /// compatibility.
        case cancelled
        /// Returned if data not cached and ``ImageRequest/Options-swift.struct/returnCacheDataDontLoad`` option is specified.
        case dataMissingInCache
        /// Data loader failed to load image data with a wrapped error.
        case dataLoadingFailed(error: Swift.Error)
        /// Data loader returned empty data.
        case dataIsEmpty
        /// No decoder registered for the given data.
        ///
        /// This error can only be thrown if the pipeline has custom decoders.
        /// By default, the pipeline uses ``ImageDecoders/Default`` as a catch-all.
        case decoderNotRegistered(context: ImageDecodingContext)
        /// Decoder failed to produce a final image.
        case decodingFailed(decoder: any ImageDecoding, context: ImageDecodingContext, error: Swift.Error)
        /// Processor failed to produce a final image.
        case processingFailed(processor: any ImageProcessing, context: ImageProcessingContext, error: Swift.Error)
        /// Load image method was called with no image request.
        case imageRequestMissing
        /// Image pipeline is invalidated and no requests can be made.
        case pipelineInvalidated
    }
}

extension ImageTask.Error {
    /// Returns underlying data loading error.
    public var dataLoadingError: Swift.Error? {
        switch self {
        case .dataLoadingFailed(let error):
            return error
        default:
            return nil
        }
    }

    public var description: String {
        switch self {
        case .dataMissingInCache:
            return "Failed to load data from cache and download is disabled."
        case let .dataLoadingFailed(error):
            return "Failed to load image data. Underlying error: \(error)."
        case .dataIsEmpty:
            return "Data loader returned empty data."
        case .decoderNotRegistered:
            return "No decoders registered for the downloaded data."
        case let .decodingFailed(decoder, _, error):
            let underlying = error is ImageDecodingError ? "" : " Underlying error: \(error)."
            return "Failed to decode image data using decoder \(decoder).\(underlying)"
        case let .processingFailed(processor, _, error):
            let underlying = error is ImageProcessingError ? "" : " Underlying error: \(error)."
            return "Failed to process the image using processor \(processor).\(underlying)"
        case .imageRequestMissing:
            return "Load image method was called with no image request or no URL."
        case .pipelineInvalidated:
            return "Image pipeline is invalidated and no requests can be made."
        case .cancelled:
            return "Image task was cancelled"
        }
    }
}
