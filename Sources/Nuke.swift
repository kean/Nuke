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

internal extension OperationQueue {
    /// Executes the given closure asynchronously on the queue by wrapping the
    /// closure in the asynchronous operation. The operation gets finished when
    /// the given `finish` closure is called.
    func execute(token: CancellationToken?, closure: @escaping (_ finish: @escaping () -> Void) -> Void) {
        if token?.isCancelling == true { return }
        let operation = Operation(starter: closure)
        addOperation(operation)
        token?.register { [weak operation] in operation?.cancel() }
    }
}

private final class Operation: Foundation.Operation {
    override var isExecuting: Bool {
        get { return _isExecuting }
        set {
            willChangeValue(forKey: "isExecuting")
            _isExecuting = newValue
            didChangeValue(forKey: "isExecuting")
        }
    }
    private var _isExecuting = false

    override var isFinished: Bool {
        get { return _isFinished }
        set {
            willChangeValue(forKey: "isFinished")
            _isFinished = newValue
            didChangeValue(forKey: "isFinished")
        }
    }
    var _isFinished = false

    let starter: (_ finish: @escaping () -> Void) -> Void
    let queue = DispatchQueue(label: "com.github.kean.Nuke.Operation")

    init(starter: @escaping (_ fulfill: @escaping () -> Void) -> Void) {
        self.starter = starter
    }

    override func start() {
        queue.sync {
            isExecuting = true
            DispatchQueue.global().async {
                self.starter { [weak self] in
                    self?.finish()
                }
            }
        }
    }

    func finish() {
        queue.sync {
            if !isFinished {
                isExecuting = false
                isFinished = true
            }
        }
    }
}
