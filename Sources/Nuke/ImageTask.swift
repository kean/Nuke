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

    /// The original request.
    public let request: ImageRequest

    /// Updates the priority of the task. The priority can be updated dynamically
    /// even if that task is already running.
    public var priority: ImageRequest.Priority {
        get { sync { _priority } }
        set { setPriority(newValue) }
    }
    private var _priority: ImageRequest.Priority

    /// Returns the current download progress. Returns zeros before the download
    /// is started and the expected size of the resource is known.
    public internal(set) var currentProgress: Progress {
        get { sync { _currentProgress } }
        set { sync { _currentProgress = newValue } }
    }
    private var _currentProgress = Progress(completed: 0, total: 0)

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
            self.completed = completed
            self.total = total
        }
    }

    /// The current state of the task.
    public var state: State { sync { _state } }
    private var _state: State = .running

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

    /// The image response.
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
    public var events: AnyPublisher<Event, Never> {
        sync { _events.eraseToAnyPublisher() }
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

    let isDataTask: Bool
    weak var pipeline: ImagePipeline?

    private var task: Task<ImageResponse, Error>!
    private var context = AsyncExecutionContext()
    private let onEvent: ((Event, ImageTask) -> Void)?
    private let lock: os_unfair_lock_t

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    init(taskId: Int64, request: ImageRequest, isDataTask: Bool, pipeline: ImagePipeline, onEvent: ((Event, ImageTask) -> Void)?) {
        self.taskId = taskId
        self.request = request
        self._priority = request.priority
        self.isDataTask = isDataTask
        self.pipeline = pipeline
        self.onEvent = onEvent

        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())

        task = Task {
            try await withUnsafeThrowingContinuation { continuation in
                self.sync { self.context.continuation = continuation }
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
        "ImageTask(id: \(taskId), priority: \(_priority), progress: \(currentProgress.completed) / \(currentProgress.total), state: \(state))"
    }

    // MARK: Internals

    private func setPriority(_ newValue: ImageRequest.Priority) {
        let didChange: Bool = sync {
            guard _priority != newValue else { return false }
            _priority = newValue
            return _state == .running
        }
        guard didChange else { return }
        pipeline?.imageTaskUpdatePriorityCalled(self, priority: newValue)
    }

    private func setState(_ state: ImageTask.State) -> Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }

        guard _state == .running else { return false }
        _state = state
        return true
    }

    func process(_ event: Event) {
        switch event {
        case .progress(let progress):
            currentProgress = progress
        case .finished:
            guard setState(.completed) else { return }
        default:
            break
        }
        process(event, in: sync { context })
        onEvent?(event, self)
        pipeline?.imageTask(self, didProcessEvent: event)
    }

    private func process(_ event: Event, in context: AsyncExecutionContext) {
        context.events?.send(event)
        switch event {
        case .cancelled:
            context.events?.send(completion: .finished)
            context.continuation?.resume(throwing: CancellationError())
        case .finished(let result):
            let result = result.mapError { $0 as Error }
            context.events?.send(completion: .finished)
            context.continuation?.resume(with: result)
        default:
            break
        }
    }

    private func sync<T>(_ closure: () -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return closure()
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

// MARK: - ImageTask (Async)

extension ImageTask {
    private func makeStream<T>(of closure: @escaping (Event) -> T?) -> AsyncStream<T> {
        AsyncStream { continuation in
            guard let events = _eventIfNotCompleted else {
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

    private var _eventIfNotCompleted: PassthroughSubject<Event, Never>? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        guard _state == .running else { return nil }
        return _events
    }

    private var _events: PassthroughSubject<Event, Never> {
        if context.events == nil {
            context.events = PassthroughSubject()
        }
        return context.events!
    }

    private struct AsyncExecutionContext {
        var continuation: UnsafeContinuation<ImageResponse, Error>?
        var events: PassthroughSubject<Event, Never>?
    }
}
