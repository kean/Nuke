// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation

#if os(macOS)
    import AppKit.NSImage
    /// Alias for `NSImage`.
    public typealias Image = NSImage
#else
    import UIKit.UIImage
    /// Alias for `UIImage`.
    public typealias Image = UIImage
#endif


/// An enum representing either a success with a result value, or a failure.
public enum Result<T> {
    case success(T), failure(Error)

    /// Returns a `value` if the result is success.
    public var value: T? {
        if case let .success(val) = self { return val } else { return nil }
    }

    /// Returns an `error` if the result is failure.
    public var error: Error? {
        if case let .failure(err) = self { return err } else { return nil }
    }
}

// MARK: - Internals

internal final class Lock {
    var mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)

    init() { pthread_mutex_init(mutex, nil) }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deinitialize()
        mutex.deallocate(capacity: 1)
    }

    // In performance critical places using lock() and unlock() is slightly
    // faster than using `sync(_:)` method.
    func sync<T>(_ closure: () -> T) -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return closure()
    }

    func lock() { pthread_mutex_lock(mutex) }
    func unlock() { pthread_mutex_unlock(mutex) }
}

internal extension DispatchQueue {
    func execute(token: CancellationToken?, closure: @escaping () -> Void) {
        if token?.isCancelling == true { return }
        let work = DispatchWorkItem(block: closure)
        async(execute: work)
        token?.register { [weak work] in work?.cancel() }
    }
}

// MARK: - TaskQueue

/// Limits number of maximum concurrent tasks.
public class TaskQueue {
    // An alternative of using custom Foundation.Operation requires more code,
    // less performant and even harder to get right https://github.com/kean/Nuke/issues/141.
    private var executingTaskCount: Int = 0
    private var pendingTasks = LinkedList<Task>()
    private let maxConcurrentTaskCount: Int
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.Queue")

    public init(maxConcurrentTaskCount: Int) {
        self.maxConcurrentTaskCount = maxConcurrentTaskCount
    }

    public func execute(token: CancellationToken?, closure: @escaping (_ finish: @escaping () -> Void) -> Void) {
        queue.async {
            if token?.isCancelling == true { return } // fast preflight check
            let task = Task(token: token, execute: closure)
            self.pendingTasks.append(LinkedList.Node(value: task))
            self._executeTasksIfNecessary()
        }
    }

    private func _executeTasksIfNecessary() {
        while executingTaskCount < maxConcurrentTaskCount, let task = pendingTasks.tail {
            pendingTasks.remove(task)
            _executeTask(task.value)
        }
    }

    private func _executeTask(_ task: Task) {
        if task.token?.isCancelling == true { return } // fast preflight check
        executingTaskCount += 1
        task.execute { [weak self] in
            self?.queue.async {
                guard !task.isFinished else { return } // finish called twice
                task.isFinished = true
                self?.executingTaskCount -= 1
                self?._executeTasksIfNecessary()
            }
        }
    }

    private final class Task {
        let token: CancellationToken?
        let execute: (_ finish: @escaping () -> Void) -> Void
        var isFinished: Bool = false

        init(token: CancellationToken?, execute: @escaping (_ finish: @escaping () -> Void) -> Void) {
            self.token = token
            self.execute = execute
        }
    }
}
