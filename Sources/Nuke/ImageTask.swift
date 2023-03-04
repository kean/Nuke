// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

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

    /// Updates the priority of the task, even if it is already running.
    public var priority: ImageRequest.Priority {
        get { sync { _priority } }
        set {
            let didChange: Bool = sync {
                guard _priority != newValue else { return false }
                _priority = newValue
                return _state == .running
            }
            guard didChange else { return }
            pipeline?.imageTaskUpdatePriorityCalled(self, priority: newValue)
        }
    }
    private var _priority: ImageRequest.Priority

    /// Returns the current download progress. Returns zeros before the download
    /// is started and the expected size of the resource is known.
    public internal(set) var progress: Progress {
        get { sync { _progress } }
        set { sync { _progress = newValue } }
    }
    private var _progress = Progress(completed: 0, total: 0)

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

    var onCancel: (() -> Void)?

    weak var pipeline: ImagePipeline?
    var callbackQueue: DispatchQueue?
    var isDataTask = false

    /// Using it without a wrapper to reduce the number of allocations.
    private let lock: os_unfair_lock_t

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    init(taskId: Int64, request: ImageRequest) {
        self.taskId = taskId
        self.request = request
        self._priority = request.priority

        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    /// Marks task as being cancelled.
    ///
    /// The pipeline will immediately cancel any work associated with a task
    /// unless there is an equivalent outstanding task running.
    public func cancel() {
        os_unfair_lock_lock(lock)
        guard _state == .running else {
            return os_unfair_lock_unlock(lock)
        }
        _state = .cancelled
        os_unfair_lock_unlock(lock)

        pipeline?.imageTaskCancelCalled(self)
    }

    func didComplete() {
        os_unfair_lock_lock(lock)
        guard _state == .running else {
            return os_unfair_lock_unlock(lock)
        }
        _state = .completed
        os_unfair_lock_unlock(lock)
    }

    private func sync<T>(_ closure: () -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return closure()
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
        "ImageTask(id: \(taskId), priority: \(_priority), progress: \(progress.completed) / \(progress.total), state: \(state))"
    }
}
