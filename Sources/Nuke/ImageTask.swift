// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
@preconcurrency import Combine

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
@ImagePipelineActor
public final class ImageTask: Hashable {
    /// An identifier that uniquely identifies the task within a given pipeline.
    /// Unique only within that pipeline.
    public nonisolated let taskId: Int64

    /// The original request that the task was created with.
    public nonisolated let request: ImageRequest

    /// The priority of the task. The priority can be updated dynamically even
    /// for a task that is already running.
    public nonisolated var priority: ImageRequest.Priority {
        get { nonisolatedState.withLock(\.priority) }
        set { setPriority(newValue) }
    }

    /// Returns the current download progress. Returns zeros before the download
    /// is started and the expected size of the resource is known.
    public nonisolated var currentProgress: Progress {
        nonisolatedState.withLock(\.progress)
    }

    /// The current state of the task.
    public private(set) var state: State = .suspended

    /// Returns `true` if the task cancellation is initiated.
    public nonisolated var isCancelling: Bool {
        nonisolatedState.withLock(\.isCancelling)
    }

    // MARK: - Async/Await

    /// Returns the response image.
    public var image: PlatformImage {
        get async throws(ImagePipeline.Error) {
            try await response.image
        }
    }

    /// Returns the image response.
    public var response: ImageResponse {
        get async throws(ImagePipeline.Error) {
            try await perform()
        }
    }

    /// The stream of progress updates.
    public nonisolated var progress: AsyncStream<Progress> {
        makeStream {
            if case .progress(let value) = $0 { return value }
            return nil
        }
    }

    /// The stream of image previews generated for images that support
    /// progressive decoding.
    ///
    /// - seealso: ``ImagePipeline/Configuration-swift.struct/isProgressiveDecodingEnabled``
    public nonisolated var previews: AsyncStream<ImageResponse> {
        makeStream {
            if case .preview(let value) = $0 { return value }
            return nil
        }
    }

    // MARK: - Events

    /// The events sent by the pipeline during the task execution.
    public nonisolated var events: AsyncStream<Event> { makeStream { $0 } }

    let isDataTask: Bool
    private let nonisolatedState: Mutex<ImageTaskState>
    private let onEvent: (@Sendable (Event, ImageTask) -> Void)?
    private weak var pipeline: ImagePipeline?
    private var subscription: TaskSubscription?

    // TODO: optimize (store one inline)
    private var continuations = ContiguousArray<UnsafeContinuation<ImageResponse, Error>>()
    private var _events: PassthroughSubject<ImageTask.Event, Never>?

    nonisolated init(taskId: Int64, request: ImageRequest, isDataTask: Bool, pipeline: ImagePipeline, onEvent: (@Sendable (Event, ImageTask) -> Void)?) {
        self.taskId = taskId
        self.request = request
        self.nonisolatedState = Mutex(ImageTaskState(priority: request.priority))
        self.isDataTask = isDataTask
        self.pipeline = pipeline
        self.onEvent = onEvent
    }

    private func perform() async throws(ImagePipeline.Error) -> ImageResponse {
        do {
            return try await withTaskCancellationHandler {
                try await withUnsafeThrowingContinuation {
                    switch state {
                    case .suspended:
                        continuations.append($0)
                        startRunning()
                    case .running:
                        continuations.append($0)
                    case .cancelled:
                        $0.resume(throwing: ImagePipeline.Error.cancelled)
                    case .completed(let result):
                        $0.resume(with: result)
                    }
                }
            } onCancel: {
                cancel()
            }
        } catch {
            // swiftlint:disable:next force_cast
            throw error as! ImagePipeline.Error
        }
    }

    private func startRunning() {
        state = .running
        subscription = pipeline?.perform(self) { [weak self] in
            self?.process($0)
        }
    }

    /// Marks task as being cancelled.
    ///
    /// The pipeline will immediately cancel any work associated with a task
    /// unless there is an equivalent outstanding task running.
    public nonisolated func cancel() {
        guard nonisolatedState.withLock({
            guard !$0.isCancelling else { return false }
            $0.isCancelling = true
            return true
        }) else { return }
        Task { @ImagePipelineActor in
            _cancel()
        }
    }

    private nonisolated func setPriority(_ newValue: ImageRequest.Priority) {
        guard nonisolatedState.withLock({
            guard $0.priority != newValue else { return false }
            $0.priority = newValue
            return !$0.isCancelling
        }) else { return }
        Task { @ImagePipelineActor in
            subscription?.setPriority(TaskPriority(newValue))
        }
    }

    // MARK: Internals

    /// Gets called when the task is cancelled either by the user or by an
    /// external event such as session invalidation.
    func _cancel() {
        guard case .running = state else { return }
        subscription?.unsubscribe()
        subscription = nil
        state = .cancelled
        dispatch(.cancelled)
    }

    /// Gets called when the associated task sends a new event.
    private func process(_ event: AsyncTask<ImageResponse, ImagePipeline.Error>.Event) {
        guard case .running = state else { return }
        switch event {
        case let .value(response, isCompleted):
            if isCompleted {
                state = .completed(.success(response))
                dispatch(.finished(.success(response)))
            } else {
                dispatch(.preview(response))
            }
        case let .progress(value):
            nonisolatedState.withLock { $0.progress = value }
            dispatch(.progress(value))
        case let .error(error):
            state = .completed(.failure(error))
            dispatch(.finished(.failure(error)))
        }
    }

    /// Dispatches the given event to the observers.
    ///
    /// - warning: The task needs to be fully wired (`_continuation` present)
    /// before it can start sending the events.
    private func dispatch(_ event: Event) {
        _events?.send(event)

        func complete(with result: Result<ImageResponse, ImagePipeline.Error>) {
            subscription = nil
            _events?.send(completion: .finished)
            for continuation in continuations {
                continuation.resume(with: result)
            }
            continuations = []
        }

        switch event {
        case .cancelled:
            complete(with: .failure(.cancelled))
        case .finished(let result):
            complete(with: result)
        default:
            break
        }

        onEvent?(event, self)
        pipeline?.imageTask(self, didProcessEvent: event)
    }

    // MARK: Hashable

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self).hashValue)
    }

    public nonisolated static func == (lhs: ImageTask, rhs: ImageTask) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

// MARK: - ImageTask (Private)

extension ImageTask {
    private nonisolated func makeStream<T>(of closure: @Sendable @escaping (Event) -> T?) -> AsyncStream<T> {
        AsyncStream { continuation in
            Task { @ImagePipelineActor in
                if case .suspended = state {
                    startRunning()
                }
                guard case .running = state else {
                    return continuation.finish()
                }
                let cancellable = makeEvents().sink { _ in
                    continuation.finish()
                } receiveValue: { event in
                    if let value = closure(event) {
                        continuation.yield(value)
                    }
                    switch event {
                    case .cancelled, .finished:
                        continuation.finish()
                    default:
                        break
                    }
                }
                continuation.onTermination = { _ in
                    cancellable.cancel()
                }
            }
        }
    }

    private func makeEvents() -> PassthroughSubject<ImageTask.Event, Never> {
        if _events == nil {
            _events = PassthroughSubject()
        }
        return _events!
    }
}

private struct ImageTaskState {
    var isCancelling = false
    var priority: ImageRequest.Priority
    var progress = ImageTask.Progress(completed: 0, total: 0)
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
    public enum State: Sendable {
        /// The initial state.
        case suspended
        /// The task is currently running.
        case running
        /// The task has received a cancel message.
        case cancelled
        /// The task has completed (without being canceled).
        case completed(Result<ImageResponse, ImagePipeline.Error>)
    }

    /// An event produced during the runetime of the task.
    public enum Event: Sendable {
        /// The download progress was updated.
        case progress(Progress)
        /// The pipeline generated a progressive scan of the image.
        case preview(ImageResponse)
        /// The task was cancelled.
        ///
        /// - note: You are guaranteed to receive either `.cancelled` or
        /// `.finished`, but never both.
        case cancelled
        /// The task finish with the given response.
        case finished(Result<ImageResponse, ImagePipeline.Error>)
    }
}
