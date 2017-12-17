// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Manages cancellation tokens and signals them when cancellation is requested.
///
/// All `CancellationTokenSource` methods are thread safe.
public final class CancellationTokenSource {
    /// Returns `true` if cancellation has been requested for this token.
    public var isCancelling: Bool {
        _lock.lock(); defer { _lock.unlock() }
        return _observers == nil
    }

    /// Creates a new token associated with the source.
    public var token: CancellationToken { return CancellationToken(source: self) }

    private var _observers: [() -> Void]? = []

    /// Initializes the `CancellationTokenSource` instance.
    public init() {}

    fileprivate func register(_ closure: @escaping () -> Void) {
        if !_register(closure) {
            closure()
        }
    }

    private func _register(_ closure: @escaping () -> Void) -> Bool {
        _lock.lock(); defer { _lock.unlock() }
        _observers?.append(closure)
        return _observers != nil
    }

    /// Communicates a request for cancellation to the managed token.
    public func cancel() {
        if let observers = _cancel() {
            observers.forEach { $0() }
        }
    }

    private func _cancel() -> [() -> Void]? {
        _lock.lock(); defer { _lock.unlock() }
        let observers = _observers
        _observers = nil // transition to `isCancelling` state
        return observers
    }
}

// We use the same lock across differnet tokens because the design of CTS
// prevents potential issues. For example, closures registered with a token
// are never executed inside a lock.
private let _lock = Lock()

/// Enables cooperative cancellation of operations.
///
/// You create a cancellation token by instantiating a `CancellationTokenSource`
/// object and calling its `token` property. You then pass the token to any
/// number of threads, tasks, or operations that should receive notice of
/// cancellation. When the  owning object calls `cancel()`, the `isCancelling`
/// property on every copy of the cancellation token is set to `true`.
/// The registered objects can respond in whatever manner is appropriate.
///
/// All `CancellationToken` methods are thread safe.
public struct CancellationToken {
    fileprivate let source: CancellationTokenSource

    /// Returns `true` if cancellation has been requested for this token.
    public var isCancelling: Bool { return source.isCancelling }

    /// Registers the closure that will be called when the token is canceled.
    /// If this token is already cancelled, the closure will be run immediately
    /// and synchronously.
    /// - warning: Make sure that you don't capture token inside a closure to
    /// avoid retain cycles.
    public func register(closure: @escaping () -> Void) { source.register(closure) }
}
