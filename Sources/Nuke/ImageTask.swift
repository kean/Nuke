// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Combine

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
    /// Unique only within that pipeline.
    public let taskId: Int64

    /// The original request that the task was created with.
    public let request: ImageRequest

    /// The priority of the task. The priority can be updated dynamically even
    /// for a task that is already running.
    public var priority: ImageRequest.Priority {
        get { withState { $0.priority } }
        set { setPriority(newValue) }
    }

    /// Returns the current download progress. Returns zeros before the download
    /// is started and the expected size of the resource is known.
    public var currentProgress: Progress {
        withState { $0.progress }
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

        /// Initializes progress with the given status.
        public init(completed: Int64, total: Int64) {
            (self.completed, self.total) = (completed, total)
        }
    }

    /// The current state of the task.
    public var state: State {
        withState { $0.taskState }
    }

    /// The state of the image task.
    public enum State {
        /// The task is currently running.
        case running
        /// The task has received a cancel message.
        case cancelled
        /// The task has completed (without being canceled).
        case completed
    }

    // MARK: - Async/Await

    /// Returns the response image.
    public var image: PlatformImage {
        get async throws {
            try await response.image
        }
    }

    /// Returns the image response.
    public var response: ImageResponse {
        get async throws {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                cancel()
            }
        }
    }

    /// The stream of progress updates.
    public var progress: AsyncStream<Progress> {
        makeStream {
            if case .progress(let value) = $0 { return value }
            return nil
        }
    }

    /// The stream of image previews generated for images that support
    /// progressive decoding.
    ///
    /// - seealso: ``ImagePipeline/Configuration-swift.struct/isProgressiveDecodingEnabled``
    public var previews: AsyncStream<ImageResponse> {
        makeStream {
            if case .preview(let value) = $0 { return value }
            return nil
        }
    }

    // MARK: - Events

    /// The events sent by the pipeline during the task execution.
    public var events: AsyncStream<Event> { makeStream { $0 } }

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

    let isDataTask: Bool

    private weak var pipeline: ImagePipeline?
    private var task: Task<ImageResponse, Error>!
    private var mutableState: MutableState
    private let onEvent: ((Event, ImageTask) -> Void)?
    private let lock: os_unfair_lock_t

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    init(taskId: Int64, request: ImageRequest, isDataTask: Bool, pipeline: ImagePipeline, onEvent: ((Event, ImageTask) -> Void)?) {
        self.taskId = taskId
        self.request = request
        self.mutableState = MutableState(priority: request.priority)
        self.isDataTask = isDataTask
        self.pipeline = pipeline
        self.onEvent = onEvent

        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())

        // Important to call it before `imageTaskStartCalled`
        if !isDataTask {
            pipeline.delegate.imageTaskCreated(self, pipeline: pipeline)
        }

        task = Task {
            try await withUnsafeThrowingContinuation { continuation in
                self.withState { $0.continuation = continuation }
                pipeline.imageTaskStartCalled(self)
            }
        }
    }

    /// Marks task as being cancelled.
    ///
    /// The pipeline will immediately cancel any work associated with a task
    /// unless there is an equivalent outstanding task running.
    public func cancel() {
        guard setState(.cancelled) else { return }
        pipeline?.imageTaskCancelCalled(self)
    }

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self).hashValue)
    }

    public static func == (lhs: ImageTask, rhs: ImageTask) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    // MARK: CustomStringConvertible

    public var description: String {
        "ImageTask(id: \(taskId), priority: \(priority), progress: \(currentProgress.completed) / \(currentProgress.total), state: \(state))"
    }

    // MARK: Internals

    private func setPriority(_ newValue: ImageRequest.Priority) {
        let didChange: Bool = withState {
            guard $0.priority != newValue else { return false }
            $0.priority = newValue
            return $0.taskState == .running
        }
        guard didChange else { return }
        pipeline?.imageTaskUpdatePriorityCalled(self, priority: newValue)
    }

    private func setState(_ state: ImageTask.State) -> Bool {
        withState {
            guard $0.taskState == .running else { return false }
            $0.taskState = state
            return true
        }
    }

    func process(_ event: Event) {
        let state: MutableState? = withState {
            switch event {
            case .progress(let progress):
                $0.progress = progress
            case .finished:
                guard $0.taskState == .running else { return nil }
                $0.taskState = .completed
            default:
                break
            }
            return $0
        }
        guard let state else { return }

        process(event, in: state)
        onEvent?(event, self)
        pipeline?.imageTask(self, didProcessEvent: event)
    }

    private func process(_ event: Event, in state: MutableState) {
        state.events?.send(event)
        switch event {
        case .cancelled:
            state.events?.send(completion: .finished)
            state.continuation?.resume(throwing: CancellationError())
        case .finished(let result):
            let result = result.mapError { $0 as Error }
            state.events?.send(completion: .finished)
            state.continuation?.resume(with: result)
        default:
            break
        }
    }
}

@available(*, deprecated, renamed: "ImageTask", message: "Async/Await support was added directly to the existing `ImageTask` type")
public typealias AsyncImageTask = ImageTask

extension ImageTask.Event {
    init(_ event: AsyncTask<ImageResponse, ImagePipeline.Error>.Event) {
        switch event {
        case let .value(response, isCompleted):
            if isCompleted {
                self = .finished(.success(response))
            } else {
                self = .preview(response)
            }
        case let .progress(value):
            self = .progress(value)
        case let .error(error):
            self = .finished(.failure(error))
        }
    }
}

// MARK: - ImageTask (Private)

extension ImageTask {
    private func makeStream<T>(of closure: @escaping (Event) -> T?) -> AsyncStream<T> {
        AsyncStream { continuation in
            let events: PassthroughSubject<Event, Never>? = withState {
                guard $0.taskState == .running else { return nil }
                return $0.makeEvents()
            }
            guard let events else {
                return continuation.finish()
            }
            let cancellable = events.sink { _ in
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

    private func withState<T>(_ closure: (inout MutableState) -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return closure(&mutableState)
    }

    /// Contains all the mutable task state.
    ///
    /// - warning: Must be accessed using `withState`.
    private struct MutableState {
        var taskState: ImageTask.State = .running
        var priority: ImageRequest.Priority
        var progress = Progress(completed: 0, total: 0)
        var continuation: UnsafeContinuation<ImageResponse, Error>?
        var events: PassthroughSubject<Event, Never>?

        mutating func makeEvents() -> PassthroughSubject<Event, Never> {
            if events == nil {
                events = PassthroughSubject()
            }
            return events!
        }
    }
}
