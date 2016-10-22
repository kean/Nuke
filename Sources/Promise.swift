// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A promise represents a value which may be available now, or in the future,
/// or never. Use `then()` to get the result of the promise. Use `catch()`
/// to catch errors.
///
/// Promises start in a *pending* state and *resolve* with a value to become
/// *fulfilled* or an `Error` to become *rejected*.
///
/// `Nuke.Promise` is a variant of [Pill.Promise](https://github.com/kean/Pill)
/// with simplified APIs (adds `completion`, doesn't allow `throws`, etc).
/// The `Promise` is built into Nuke to avoid fetching external dependencies.
public final class Promise<T> {
    private var state: PromiseState<T> = .pending(PromiseHandlers<T>())
    private let lock = Lock()

    /// Creates a new, pending promise.
    ///
    /// - parameter closure: The closure is called immediately on the current
    /// thread. You should start an asynchronous task and call either `fulfill`
    /// or `reject` when it completes.
    public init(_ closure: (_ fulfill: @escaping (T) -> Void, _ reject: @escaping (Error) -> Void) -> Void) {
        closure({ self._resolve(.fulfilled($0)) }, { self._resolve(.rejected($0)) })
    }

    /// Creates a promise fulfilled with a given value.
    public init(value: T) { state = .resolved(.fulfilled(value)) }

    /// Create a promise rejected with a given error.
    public init(error: Error) { state = .resolved(.rejected(error)) }

    private func _resolve(_ resolution: PromiseResolution<T>) {
        lock.lock(); defer { lock.unlock() }
        if case let .pending(handlers) = state {
            state = .resolved(resolution)
            handlers.objects.forEach { $0(resolution) }
        }
    }
    
    // MARK: Callbacks
    
    private func _observe(on queue: DispatchQueue = .main, _ closure: @escaping (PromiseResolution<T>) -> Void) {
        let _closure: (PromiseResolution<T>) -> Void = { res in queue.async { closure(res) } }
        
        // Handlers only contain `queue.async` calls which are fast
        // enough for a critical section (no real need to optimize this).
        lock.lock(); defer { lock.unlock() }
        switch state {
        case let .pending(handlers): handlers.objects.append(_closure)
        case let .resolved(resolution): _closure(resolution)
        }
    }
    
    private func _observe(on queue: DispatchQueue = .main, fulfill: ((T) -> Void)?, reject: ((Error) -> Void)?) {
        _observe(on: queue) {
            switch $0 {
            case let .fulfilled(val): fulfill?(val)
            case let .rejected(err): reject?(err)
            }
        }
    }
    
    // MARK: Completion
    
    /// The given closure executes asynchronously when the promise resolves.
    ///
    /// - parameter on: A queue on which the closure is executed. `.main` by default.
    /// - returns: self
    public func completion(on queue: DispatchQueue = .main, _ closure: @escaping (PromiseResolution<T>) -> Void) {
        _observe(on: queue, closure)
    }
    
    // MARK: Then

    /// The given closures executes asynchronously when the promise resolves.
    ///
    /// - parameter on: A queue on which the closure is run. `.main` by default.
    /// - returns: self
    @discardableResult public func then(on queue: DispatchQueue = .main, fulfilment: ((T) -> Void)?, rejection: ((Error) -> Void)?) -> Promise<T> {
        _observe(on: queue, fulfill: fulfilment, reject: rejection)
        return self
    }
    
    /// The given closure executes asynchronously when the promise is fulfilled.
    ///
    /// - parameter on: A queue on which the closure is run. `.main` by default.
    /// - returns: self
    @discardableResult public func then(on queue: DispatchQueue = .main, _ closure: @escaping (T) -> Void) -> Promise<T> {
        return then(on: queue, fulfilment: closure, rejection: nil)
    }
    
    /// The given closure executes asynchronously when the promise is fulfilled.
    ///
    /// - parameter on: A queue on which the closure is run. `.main` by default.
    /// - returns: A promise fulfilled with a value returned by the closure.
    @discardableResult public func then<U>(on queue: DispatchQueue = .main, _ closure: @escaping (T) -> U) -> Promise<U> {
        return _then(on: queue) { value, fulfill, _ in
            fulfill(closure(value))
        }
    }
    
    /// The given closure executes asynchronously when the promise is fulfilled.
    ///
    /// - parameter on: A queue on which the closure is run. `.main` by default.
    /// - returns: A promise that resolves by the promise returned by the closure.
    @discardableResult public func then<U>(on queue: DispatchQueue = .main, _ closure: @escaping (T) -> Promise<U>) -> Promise<U> {
        return _then(on: queue) { value, fulfill, reject in
            closure(value)._observe(on: queue, fulfill: fulfill, reject: reject)
        }
    }
    
    /// Returns a new promise.
    /// - when `self` is fufilled the closure is called (you control it)
    /// - when `self` is rejected the promise is rejected
    private func _then<U>(on queue: DispatchQueue, _ closure: @escaping (T, @escaping (U) -> Void, @escaping (Error) -> Void) -> Void) -> Promise<U> {
        return Promise<U>() { fulfill, reject in
            _observe(on: queue, fulfill: { closure($0, fulfill, reject) }, reject: reject)
        }
    }
    
    // MARK: Catch

    /// The given closure executes asynchronously when the promise is rejected.
    ///
    /// A promise bubbles up errors. It allows you to catch all errors returned
    /// by a chain of promises with a single `catch()`.
    ///
    /// - parameter on: A queue on which the closure is run. `.main` by default.
    @discardableResult public func `catch`(on queue: DispatchQueue = .main, _ closure: @escaping (Error) -> Void) -> Promise<T> {
        return then(on: queue, fulfilment: nil, rejection: closure)
    }
    
    /// Unlike `catch` `recover` allows you to continue the chain of promises
    /// by recovering from the error by creating a new promise.
    ///
    /// - parameter on: A queue on which the closure is run. `.main` by default.
    /// - returns: A promise that resolves by the promise returned by the closure.
    @discardableResult public func recover(on queue: DispatchQueue = .main, _ closure: @escaping (Error) -> Promise<T>) -> Promise<T> {
        return _catch(on: queue) { error, fulfill, reject in
            closure(error)._observe(on: queue, fulfill: fulfill, reject: reject)
        }
    }
    
    /// Returns a new promise.
    /// - when `self` is fufilled the promise is fulfilled
    /// - when `self` is rejected the closure is called (you control it)
    private func _catch(on queue: DispatchQueue, _ closure: @escaping (Error, @escaping (T) -> Void, @escaping (Error) -> Void) -> Void) -> Promise<T> {
        return Promise<T>() { fulfill, reject in
            _observe(on: queue, fulfill: fulfill, reject: { closure($0, fulfill, reject) })
        }
    }
    
    // MARK: Synchronous Inspection
    
    /// Returns `true` if the promise is still pending.
    public var isPending: Bool { return resolution == nil }
    
    /// Returns resolution if the promise has already resolved.
    public var resolution: PromiseResolution<T>? { return lock.sync { state.resolution } }
}

private final class PromiseHandlers<T> {
    var objects = [(PromiseResolution<T>) -> Void]() // boxed closures
}

private enum PromiseState<T> {
    case pending(PromiseHandlers<T>), resolved(PromiseResolution<T>)

    var resolution: PromiseResolution<T>? {
        if case let .resolved(res) = self { return res } else { return nil }
    }
}

/// Represents a *resolution* (result) of a promise.
public enum PromiseResolution<T> {
    case fulfilled(T), rejected(Error)

    /// Returns the `value` which promise was `fulfilled` with.
    public var value: T? {
        if case let .fulfilled(val) = self { return val } else { return nil }
    }

    /// Returns the `error` which promise was `rejected` with.
    public var error: Error? {
        if case let .rejected(err) = self { return err } else { return nil }
    }
}
