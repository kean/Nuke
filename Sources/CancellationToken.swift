// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Manages cancellation tokens and signals them when cancellation is requested.
///
/// All `CancellationTokenSource` methods are thread safe.
public final class CancellationTokenSource {
    public private(set) var isCancelling = false
    private var observers = [(Void) -> Void]()
    private let lock: Lock
    
    public var token: CancellationToken {
        return CancellationToken(source: self)
    }
    
    public init() {
        self.lock = Lock()
    }
    
    // Allows to create cts with a shared mutex to avoid excessive allocations.
    // This optimization gives you small wins in absolute numbers. It's also
    // tricky to get right thus `internal` access modifier.
    internal init(lock: Lock) { self.lock = lock }
    internal static let lock = Lock()
    
    fileprivate func register(_ closure: @escaping (Void) -> Void) {
        if isCancelling { closure(); return } // fast pre-lock check
        lock.sync {
            if isCancelling {
                closure()
            } else {
                observers.append(closure)
            }
        }
    }

    /// Communicates a request for cancellation to the managed token.
    public func cancel() {
        if isCancelling { return } // fast pre-lock check
        lock.sync {
            if !isCancelling {
                isCancelling = true
                observers.forEach { $0() }
                observers.removeAll()
            }
        }
    }
}

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
    public func register(closure: @escaping (Void) -> Void) { source.register(closure) }
}
