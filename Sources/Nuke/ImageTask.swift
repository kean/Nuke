// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// A task performed by the ``ImagePipeline``.
///
/// The pipeline starts executing a task the moment it is created. Await its
/// ``image`` or ``response`` to get the result, and observe ``progress``,
/// ``previews``, or ``events`` to follow it while it runs.
///
/// ```swift
/// let task = ImagePipeline.shared.imageTask(with: url)
/// Task {
///     for await progress in task.progress {
///         print("Downloaded \(progress.fraction * 100)%")
///     }
/// }
/// let image = try await task.image
/// ```
///
/// Use ``cancel()`` to stop the task, or cancel the Swift concurrency task that
/// awaits ``response`` – the pipeline treats both the same way.
///
/// The pipeline maintains a strong reference to the task until the request
/// finishes or fails; you do not need to maintain a reference to the task unless
/// it is useful for your app.
public final class ImageTask: Hashable, Identifiable, CustomStringConvertible, @unchecked Sendable {
    /// An identifier that uniquely identifies the task within a given pipeline.
    public let taskId: UInt64

    /// The original request that the task was created with.
    public let request: ImageRequest

    /// The priority of the task. The priority can be updated dynamically even
    /// for a task that is already running.
    public var priority: ImageRequest.Priority {
        get { _status.withLock { $0.priority } }
        set { setPriority(newValue) }
    }

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

        /// Initializes progress with the given byte counts.
        public init(completed: Int64, total: Int64) {
            (self.completed, self.total) = (completed, total)
        }
    }

    /// Returns `true` if the task was cancelled from the outside: either by
    /// calling ``cancel()``, or by cancelling the Swift concurrency task that
    /// awaits ``response``.
    ///
    /// The flag is set synchronously, on the thread that requests the
    /// cancellation, and never goes back to `false`.
    ///
    /// - note: Cancellation is a request, not an outcome. It is recorded before
    /// the pipeline sends ``Event/finished(_:)``, and it can also be requested
    /// after the task has already finished. Use ``Status/result`` to learn how
    /// the task actually ended.
    public var isCancelled: Bool {
        _status.withLock { $0.isCancelled }
    }

    /// Returns a snapshot of everything about the task that can change while
    /// it runs.
    ///
    /// Reading the individual properties one by one acquires the task's lock
    /// once per property, so the values can come from different points in time.
    /// Read the status instead when you need them to agree with each other.
    public var status: Status {
        _status.withLock { $0 }
    }

    /// A snapshot of the task state, captured at a single point in time.
    public struct Status: Sendable {
        /// The result the task finished with, or `nil` if it is still running.
        ///
        /// The result is recorded immediately before the ``Event/finished(_:)``
        /// event is sent, so it is guaranteed to be available to the observers
        /// of that event and to anyone awaiting ``ImageTask/response``.
        public internal(set) var result: Result<ImageResponse, ImagePipeline.Error>?

        /// Returns `true` if the task was cancelled from the outside.
        ///
        /// - seealso: ``ImageTask/isCancelled``
        public internal(set) var isCancelled = false

        /// The priority of the task.
        public internal(set) var priority: ImageRequest.Priority = .normal

        /// The download progress. Contains zeros until the download starts and
        /// the total resource size is known.
        public internal(set) var progress = Progress(completed: 0, total: 0)

        /// Initializes the status describing a task that has just started.
        ///
        /// The pipeline creates the status for you – use this initializer to
        /// construct one for tests and SwiftUI previews of the code that
        /// consumes it.
        public init() {}

        init(priority: ImageRequest.Priority) {
            self.priority = priority
        }
    }

    // MARK: - Async/Await

    /// Returns the response image.
    ///
    /// Throws an ``ImagePipeline/Error`` if the request fails at any stage –
    /// loading, decoding, or processing – or ``ImagePipeline/Error/cancelled``
    /// if the task is cancelled.
    ///
    /// - seealso: ``response``
    public var image: PlatformImage {
        get async throws(ImagePipeline.Error) {
            try await response.image
        }
    }

    /// Returns the image response.
    ///
    /// Throws an ``ImagePipeline/Error`` if the request fails at any stage –
    /// loading, decoding, or processing – or ``ImagePipeline/Error/cancelled``
    /// if the task is cancelled.
    ///
    /// Cancelling the Swift concurrency task that awaits the response also
    /// cancels the image task, exactly as if you called ``cancel()``.
    ///
    /// It is safe to await the response more than once and at any point in the
    /// task lifetime, including after it has already finished – every caller
    /// gets the same outcome.
    public var response: ImageResponse {
        get async throws(ImagePipeline.Error) {
            let result = await withTaskCancellationHandler {
                await _task.value
            } onCancel: {
                cancel()
            }
            return try result.get()
        }
    }

    /// The stream of progress updates.
    ///
    /// A convenience over ``events``: every access creates a new subscription.
    public var progress: AsyncCompactMapSequence<AsyncStream<Event>, Progress> {
        events.compactMap {
            if case .progress(let value) = $0 { return value }
            return nil
        }
    }

    /// The stream of image previews generated for images that support
    /// progressive decoding.
    ///
    /// A convenience over ``events``: every access creates a new subscription.
    ///
    /// - seealso: ``ImagePipeline/Configuration-swift.struct/isProgressiveDecodingEnabled``
    public var previews: AsyncCompactMapSequence<AsyncStream<Event>, ImageResponse> {
        events.compactMap {
            if case .preview(let value) = $0 { return value }
            return nil
        }
    }

    // MARK: - Events

    /// The events sent by the pipeline during the task execution.
    ///
    /// ```swift
    /// for await event in task.events {
    ///     switch event {
    ///     case .progress(let progress): print(progress.fraction)
    ///     case .preview(let response): imageView.image = response.image
    ///     case .finished(let result): print(result)
    ///     }
    /// }
    /// ```
    ///
    /// Every access creates a new independent stream, and each one delivers the
    /// complete set of events. Reading `events` twice gives you two streams, and
    /// iterating both ``progress`` and ``previews`` creates two subscriptions –
    /// store the stream in a variable if you want a single subscription.
    ///
    /// A stream always ends with the terminal ``Event/finished(_:)`` event.
    /// Subscribing is safe at any point in the task lifetime: a stream created
    /// after the task has already finished replays the terminal event, and a
    /// stream created mid-download starts with the current
    /// ``Event/progress(_:)`` value, if any.
    ///
    /// - note: A stream buffers the events that the consumer hasn't picked up
    /// yet, so a slow consumer never misses one.
    public var events: AsyncStream<Event> { makeStream() }

    /// An event produced during the runtime of the task.
    @frozen public enum Event: Sendable {
        /// The download progress was updated.
        case progress(Progress)
        /// The pipeline generated a progressive scan of the image.
        case preview(ImageResponse)
        /// The task finished with the given response.
        ///
        /// When the task is cancelled, this is called with
        /// `.failure(``ImagePipeline/Error/cancelled``)`.
        case finished(Result<ImageResponse, ImagePipeline.Error>)
    }

    private let _status: OSAllocatedUnfairLock<Status>
    private let isDataTask: Bool
    private let onEvent: ((Event, ImageTask) -> Void)?
    private weak var pipeline: ImagePipeline?

    // Set once during creation, then read-only from `response` getter.
    nonisolated(unsafe) var _task: Task<Result<ImageResponse, ImagePipeline.Error>, Never>!
    @ImagePipelineActor var _continuation: UnsafeContinuation<Result<ImageResponse, ImagePipeline.Error>, Never>?
    @ImagePipelineActor var _isFinished = false
    @ImagePipelineActor var _streamContinuations = ContiguousArray<AsyncStream<Event>.Continuation>()
    @ImagePipelineActor var _subscription: TaskSubscription?
    @ImagePipelineActor weak var _node: LinkedList<ImageTask>.Node?

    init(taskId: UInt64, request: ImageRequest, isDataTask: Bool, pipeline: ImagePipeline, onEvent: ((Event, ImageTask) -> Void)?) {
        self.taskId = taskId
        self.request = request
        self._status = OSAllocatedUnfairLock(initialState: Status(priority: request.priority))
        self.isDataTask = isDataTask
        self.pipeline = pipeline
        self.onEvent = onEvent
    }

    /// Marks task as being cancelled.
    ///
    /// The pipeline will immediately cancel any work associated with a task
    /// unless there is an equivalent outstanding task running.
    ///
    /// The task fails with ``ImagePipeline/Error/cancelled``, and its event
    /// streams end with the matching ``Event/finished(_:)`` event. Cancellation
    /// is a request, not an outcome: ``isCancelled`` is set synchronously, but
    /// a task that is already about to finish can still succeed.
    ///
    /// The method is thread-safe and calling it more than once, or after the
    /// task has already finished, has no effect.
    public func cancel() {
        let didChange: Bool = _status.withLock {
            let didChange = !$0.isCancelled && $0.result == nil
            $0.isCancelled = true
            return didChange
        }
        // Reaching the pipeline requires a hop to its actor, which then
        // unsubscribes the task and tears down the work no one else needs,
        // so make sure it happens at most once.
        guard didChange else { return }
        Task { @ImagePipelineActor in
            self.pipeline?.imageTaskCancelCalled(self)
        }
    }

    private func setPriority(_ newValue: ImageRequest.Priority) {
        let didChange: Bool = _status.withLock {
            guard $0.priority != newValue else { return false }
            $0.priority = newValue
            return !$0.isCancelled && $0.result == nil
        }
        guard didChange else { return }
        Task { @ImagePipelineActor in
            // Read the priority instead of capturing `newValue`: the hops are
            // unordered, so a stale value could land last.
            self.pipeline?.imageTaskUpdatePriorityCalled(self, priority: self.priority)
        }
    }

    // MARK: Internals

    /// Cancels the task directly from an actor-isolated context, bypassing
    /// the lock and the actor hop used by the public `cancel()` method.
    @ImagePipelineActor func _cancelTask() {
        pipeline?.imageTaskCancelCalled(self)
    }

    /// Gets called when the task is cancelled either by the user or by an
    /// external event such as session invalidation.
    @ImagePipelineActor func _cancel() {
        _finish(.failure(.cancelled))
    }

    /// Gets called when the associated task sends a new event.
    @ImagePipelineActor func _process(_ event: AsyncTask<ImageResponse, ImagePipeline.Error>.Event) {
        switch event {
        case let .value(response, isCompleted):
            if isCompleted {
                _finish(.success(response))
            } else {
                _dispatch(.preview(response))
            }
        case let .progress(value):
            _status.withLock { $0.progress = value }
            _dispatch(.progress(value))
        case let .error(error):
            _finish(.failure(error))
        }
    }

    /// Sends the terminal event, but only the first time it is called.
    @ImagePipelineActor private func _finish(_ result: Result<ImageResponse, ImagePipeline.Error>) {
        guard !_isFinished else { return }
        _isFinished = true
        _dispatch(.finished(result))
    }

    /// Dispatches the given event to the observers.
    ///
    /// - warning: The task needs to be fully wired (`_continuation` present)
    /// before it can start sending the events.
    @ImagePipelineActor func _dispatch(_ event: Event) {
        guard _continuation != nil else {
            return // Task isn't fully wired yet
        }

        // Record the result first so that it is already visible to everyone
        // observing the terminal event.
        if case .finished(let result) = event {
            _status.withLock { $0.result = result }
        }
        for continuation in _streamContinuations {
            continuation.yield(event)
        }
        switch event {
        case .finished(let result):
            for continuation in _streamContinuations {
                continuation.finish()
            }
            _streamContinuations.removeAll()
            _continuation?.resume(returning: result)
        default:
            break
        }

        onEvent?(event, self)
        pipeline?.imageTask(self, didProcessEvent: event, isDataTask: isDataTask)
    }

    // MARK: Identifiable

    /// An identifier that uniquely identifies the task.
    ///
    /// Derived from the object identity, not from ``taskId``, which is only
    /// unique within a single pipeline.
    public var id: ObjectIdentifier { ObjectIdentifier(self) }

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public static func == (lhs: ImageTask, rhs: ImageTask) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    // MARK: CustomStringConvertible

    public var description: String {
        let status = self.status
        let state: String = switch status.result {
        case .none: status.isCancelled ? "cancelled" : "running"
        case .success: "success"
        case .failure(let error): "failure(\(error))"
        }
        return "ImageTask(id: \(taskId), priority: \(status.priority), progress: \(status.progress.completed) / \(status.progress.total), state: \(state))"
    }
}

// MARK: - ImageTask (Private)

extension ImageTask {
    /// Creates a new stream of events for this task.
    ///
    /// A subscription reaches the pipeline actor asynchronously, so the task
    /// can finish before it is registered – a memory cache hit, for example,
    /// finishes the task while the pipeline is still starting it. To make sure
    /// no subscriber misses the outcome, a stream created after the task
    /// finished replays the terminal event recorded in ``Status/result``.
    private func makeStream() -> AsyncStream<Event> {
        AsyncStream { continuation in
            Task { @ImagePipelineActor in
                let status = self.status
                if let result = status.result {
                    continuation.yield(.finished(result))
                    return continuation.finish()
                }
                // Prime the stream with the progress reported so far so that a
                // progress bar attached mid-download doesn't sit at zero until
                // the next chunk arrives.
                if status.progress.completed > 0 || status.progress.total > 0 {
                    continuation.yield(.progress(status.progress))
                }
                self._streamContinuations.append(continuation)
            }
        }
    }
}

// MARK: - ImageTask (Deprecated)

extension ImageTask {
    /// Returns the current download progress. Returns zeros until the download
    /// starts and the total resource size is known.
    ///
    /// - warning: Deprecated in Nuke 14.0. Use ``status`` instead.
    @available(*, deprecated, renamed: "status.progress", message: "Deprecated in Nuke 14.0. Use `status` to read the progress along with the rest of the task state captured at the same point in time.")
    public var currentProgress: Progress {
        _status.withLock { $0.progress }
    }

    /// The current state of the task.
    ///
    /// - warning: Deprecated in Nuke 14.0. Use ``status`` instead. The state is
    /// now derived from it: ``Status/isCancelled`` records the cancellation
    /// request and ``Status/result`` records how the task actually ended.
    @available(*, deprecated, message: "Deprecated in Nuke 14.0. Use `status` instead: `isCancelled` for the cancellation request and `result` for the outcome.")
    public var state: State {
        let status = self.status
        guard let result = status.result else {
            return status.isCancelled ? .cancelled : .running
        }
        if case .failure(.cancelled) = result {
            return .cancelled
        }
        return .completed
    }

    /// The state of the image task.
    ///
    /// - warning: Deprecated in Nuke 14.0. Use ``ImageTask/Status`` instead.
    @available(*, deprecated, message: "Deprecated in Nuke 14.0. Use `ImageTask.Status` instead.")
    @frozen public enum State {
        /// The task is currently running.
        case running
        /// The task has received a cancel message.
        case cancelled
        /// The task has completed (without being canceled).
        case completed
    }
}
