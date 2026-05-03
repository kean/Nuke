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
/// The pipeline maintains a strong reference to the task until the request
/// finishes or fails; you do not need to maintain a reference to the task unless
/// it is useful for your app.
public final class ImageTask: Hashable, CustomStringConvertible, @unchecked Sendable {
    /// An identifier that uniquely identifies the task within a given pipeline.
    public let taskId: UInt64

    /// The original request that the task was created with.
    public let request: ImageRequest

    /// The priority of the task. The priority can be updated dynamically even
    /// for a task that is already running.
    public var priority: ImageRequest.Priority {
        get { withNonisolatedStateLock { $0.priority } }
        set { setPriority(newValue) }
    }

    /// Returns the current download progress. Returns zeros until the download
    /// starts and the total resource size is known.
    public var currentProgress: Progress {
        withNonisolatedStateLock { $0.progress }
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

    /// The current state of the task.
    public var state: State {
        withNonisolatedStateLock { $0.state }
    }

    var isCancelled: Bool {
        withNonisolatedStateLock { $0.isCancelled }
    }

    /// The state of the image task.
    @frozen public enum State {
        /// The task is currently running.
        case running
        /// The task has received a cancel message.
        case cancelled
        /// The task has completed (without being canceled).
        case completed
    }

    // MARK: - Async/Await

    /// Returns the response image.
    ///
    /// Throws ``ImagePipeline/Error/cancelled`` if the task is cancelled.
    public var image: PlatformImage {
        get async throws(ImagePipeline.Error) {
            try await response.image
        }
    }

    /// Returns the image response.
    ///
    /// Throws ``ImagePipeline/Error/cancelled`` if the task is cancelled.
    public var response: ImageResponse {
        get async throws(ImagePipeline.Error) {
            do {
                return try await withTaskCancellationHandler {
                    try await _task.value
                } onCancel: {
                    cancel()
                }
            } catch let error as ImagePipeline.Error {
                throw error
            } catch {
                preconditionFailure("Unexpected error type: \(error)")
            }
        }
    }

    /// The stream of progress updates.
    public var progress: AsyncCompactMapSequence<AsyncStream<Event>, Progress> {
        events.compactMap {
            if case .progress(let value) = $0 { return value }
            return nil
        }
    }

    /// The stream of image previews generated for images that support
    /// progressive decoding.
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
    public var events: AsyncStream<Event> { makeStream() }

    /// An event produced during the runtime of the task.
    @frozen public enum Event: Sendable {
        /// The task was started by the pipeline.
        case started
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

    private var nonisolatedState: NonisolatedState
    private let isDataTask: Bool
    private let onEvent: ((Event, ImageTask) -> Void)?
    private let lock: os_unfair_lock_t
    private weak var pipeline: ImagePipeline?

    // Set once during creation, then read-only from `response` getter.
    nonisolated(unsafe) var _task: Task<ImageResponse, any Error>!
    @ImagePipelineActor var _continuation: UnsafeContinuation<ImageResponse, any Error>?
    @ImagePipelineActor var _state: State = .running
    @ImagePipelineActor var _streamContinuations = ContiguousArray<AsyncStream<Event>.Continuation>()
    @ImagePipelineActor var _subscription: TaskSubscription?
    @ImagePipelineActor weak var _node: LinkedList<ImageTask>.Node?

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    init(taskId: UInt64, request: ImageRequest, isDataTask: Bool, pipeline: ImagePipeline, onEvent: ((Event, ImageTask) -> Void)?) {
        self.taskId = taskId
        self.request = request
        self.nonisolatedState = NonisolatedState(priority: request.priority)
        self.isDataTask = isDataTask
        self.pipeline = pipeline
        self.onEvent = onEvent

        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    /// Marks task as being cancelled.
    ///
    /// The pipeline will immediately cancel any work associated with a task
    /// unless there is an equivalent outstanding task running.
    public func cancel() {
        let didChange: Bool = withNonisolatedStateLock {
            $0.isCancelled = true
            guard $0.state == .running else { return false }
            $0.state = .cancelled
            return true
        }
        guard didChange else { return } // Make sure it gets called once (expensive)
        Task { @ImagePipelineActor in
            self.pipeline?.imageTaskCancelCalled(self)
        }
    }

    private func setPriority(_ newValue: ImageRequest.Priority) {
        let didChange: Bool = withNonisolatedStateLock {
            guard $0.priority != newValue else { return false }
            $0.priority = newValue
            return $0.state == .running
        }
        guard didChange else { return }
        Task { @ImagePipelineActor in
            self.pipeline?.imageTaskUpdatePriorityCalled(self, priority: newValue)
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
        guard _setState(.cancelled) else { return }
        _dispatch(.finished(.failure(.cancelled)))
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
            withNonisolatedStateLock { $0.progress = value }
            _dispatch(.progress(value))
        case let .error(error):
            _finish(.failure(error))
        }
    }

    @ImagePipelineActor private func _finish(_ result: Result<ImageResponse, ImagePipeline.Error>) {
        guard _setState(.completed) else { return }
        _dispatch(.finished(result))
    }

    // The state mirror needs to be eliminated.
    @ImagePipelineActor func _setState(_ state: State) -> Bool {
        guard _state == .running else { return false }
        _state = state
        withNonisolatedStateLock {
            guard $0.state == .running else { return }
            $0.state = state
        }
        return true
    }

    /// Dispatches the given event to the observers.
    ///
    /// - warning: The task needs to be fully wired (`_continuation` present)
    /// before it can start sending the events.
    @ImagePipelineActor func _dispatch(_ event: Event) {
        guard _continuation != nil else {
            return // Task isn't fully wired yet
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
            _continuation?.resume(with: result)
        default:
            break
        }

        onEvent?(event, self)
        pipeline?.imageTask(self, didProcessEvent: event, isDataTask: isDataTask)
    }

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public static func == (lhs: ImageTask, rhs: ImageTask) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    // MARK: CustomStringConvertible

    public var description: String {
        "ImageTask(id: \(taskId), priority: \(priority), progress: \(currentProgress.completed) / \(currentProgress.total), state: \(state))"
    }
}

// MARK: - ImageTask (Private)

extension ImageTask {
    /// Creates a new stream of events for this task.
    ///
    /// - note: Each call creates an independent stream. Subscribing after the
    /// task has already finished or been cancelled produces an empty stream —
    /// no `.finished` terminal event is replayed. Subscribe before the task
    /// completes if you need to observe this event.
    private func makeStream() -> AsyncStream<Event> {
        AsyncStream { continuation in
            Task { @ImagePipelineActor in
                guard self._state == .running else {
                    return continuation.finish()
                }
                self._streamContinuations.append(continuation)
            }
        }
    }

    private func withNonisolatedStateLock<T>(_ closure: (inout NonisolatedState) -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return closure(&nonisolatedState)
    }

    /// Contains the state synchronized using the internal lock.
    ///
    /// - warning: Must be accessed using `withNonisolatedState`.
    private struct NonisolatedState {
        var state: ImageTask.State = .running
        var isCancelled = false
        var priority: ImageRequest.Priority
        var progress = Progress(completed: 0, total: 0)
    }
}
