// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A promise is an object that represents an asynchronous task. Use `then()`
/// to get the result of the promise. Use `catch()` to catch errors.
///
/// Promises start in a *pending* state and *resolve* with a value to become
/// *fulfilled* or an `Error` to become *rejected*.
public final class Promise<T> {
    // Promise is built into Nuke to avoid fetching external dependencies.

    private var state: PromiseState<T> = .pending(PromiseHandlers<T>())
    private let lock = Lock()

    /// Creates a new, pending promise.
    ///
    /// - parameter value: The provided closure is called immediately on the
    /// current thread. In the closure you should start an asynchronous task and
    /// call either `fulfill` or `reject` when it completes.
    public init(_ closure: (_ fulfill: @escaping (T) -> Void, _ reject: @escaping (Error) -> Void) -> Void) {
        closure({ self.resolve(.fulfilled($0)) }, { self.resolve(.rejected($0)) })
    }

    /// Creates a promise fulfilled with a given value.
    public init(value: T) {
        state = .resolved(.fulfilled(value))
    }

    /// Create a promise rejected with a given error.
    public init(error: Error) {
        state = .resolved(.rejected(error))
    }

    private func resolve(_ resolution: PromiseResolution<T>) {
        lock.lock()
        if case let .pending(handlers) = state {
            state = .resolved(resolution)
            handlers.objects.forEach { $0(resolution) }
        }
        lock.unlock()
    }

    /// The provided closure executes asynchronously when the promise resolves.
    ///
    /// - parameter on: A queue on which the closure is executed. `.main` by default.
    /// - returns: self
    @discardableResult public func completion(on queue: DispatchQueue = .main, _ closure: @escaping (PromiseResolution<T>) -> Void) -> Promise {
        let completion: (PromiseResolution<T>) -> Void = { resolution in
            queue.async { closure(resolution) }
        }
        lock.lock()
        switch state {
        case let .pending(handlers): handlers.objects.append(completion)
        case let .resolved(resolution): completion(resolution)
        }
        lock.unlock()
        return self
    }

    // MARK: Properties

    /// Returns `true` if the promise is still pending.
    public var isPending: Bool {
        return resolution == nil
    }

    /// Returns resolution if the promise has already resolved.
    public var resolution: PromiseResolution<T>? {
        return lock.sync { state.resolution }
    }
}

public extension Promise {

    /// The provided closure executes asynchronously when the promise fulfills
    /// with a value. Allows to add a handler without breaking the chain.
    ///
    /// - parameter on: A queue on which the closure is executed. `.main` by default.
    /// - returns: self
    @discardableResult public func then(on queue: DispatchQueue = .main, _ closure: @escaping (T) -> Void) -> Promise {
        return completion(on: queue, fulfill: closure, reject: nil)
    }

    /// The provided closure executes asynchronously when the promise fulfills
    /// with a value. Allows to transform `Promise<T>` to `Promise<U>`.
    ///
    /// - parameter on: A queue on which the closure is executed. `.main` by default.
    /// queue by default.
    /// - returns: A promise fulfilled with a value returns by the closure.
    public func then<U>(on queue: DispatchQueue = .main, _ closure: @escaping (T) -> U) -> Promise<U> {
        return then(on: queue) { Promise<U>(value: closure($0)) }
    }
    
    /// The provided closure executes asynchronously when the promise fulfills
    /// with a value. Allows to chain promises.
    ///
    /// - parameter on: A queue on which the closure is executed. `.main` by default.
    /// - returns: A promise that resolves with the resolution of the promise
    /// returned by the given closure.
    public func then<U>(on queue: DispatchQueue = .main, _ closure: @escaping (T) -> Promise<U>) -> Promise<U> {
        return Promise<U>() { fulfill, reject in
            completion(
                on: queue,
                fulfill: { // resolve new promise with the promise returned by the closure
                    closure($0).completion(on: queue, fulfill: fulfill, reject: reject)
                },
                reject: reject) // bubble up error
        }
    }

    /// The provided closure executes asynchronously when the promise is
    /// rejected with an error.
    ///
    /// A promise bubbles up errors. It allows you to catch all errors returned
    /// by a chain of promises with a single `catch()`.
    ///
    /// - parameter on: A queue on which the closure is executed. `.main` by default.
    @discardableResult public func `catch`(on queue: DispatchQueue = .main, _ closure: @escaping (Error) -> Void) {
        completion(on: queue, fulfill: nil, reject: closure)
    }

    /// Unlike `catch` `recover` allows you to continue the chain of promises
    /// by recovering from the error by creating a new promise.
    ///
    /// - parameter on: A queue on which the closure is executed. `.main` by default.
    public func recover(on queue: DispatchQueue = .main, _ closure: @escaping (Error) -> Promise) -> Promise {
        return Promise() { fulfill, reject in
            completion(
                on: queue,
                fulfill: fulfill, // bubble up value
                reject: { // resolve new promise with the promise returned by the closure
                    closure($0).completion(on: queue, fulfill: fulfill, reject: reject)
            })
        }
    }

    /// Private convenience method on top of `completion(on:closure:)`.
    @discardableResult private func completion(on queue: DispatchQueue = .main, fulfill: ((T) -> Void)?, reject: ((Error) -> Void)?) -> Promise {
        return completion(on: queue) {
            switch $0 {
            case let .fulfilled(val): fulfill?(val)
            case let .rejected(err): reject?(err)
            }
        }
    }

    @available(*, deprecated: 4.2, message: "Use completion() instead which now also returns a Promise")
    @discardableResult public func then(on queue: DispatchQueue = .main, fulfilment: ((T) -> Void)?, rejection: ((Error) -> Void)?) -> Promise {
        return completion(on: queue, fulfill: fulfilment, reject: rejection)
    }
}

// FIXME: make nested type when compiler adds support for it
private final class PromiseHandlers<T> {
    var objects = [(PromiseResolution<T>) -> Void]()
}

private enum PromiseState<T> {
    case pending(PromiseHandlers<T>), resolved(PromiseResolution<T>)

    var resolution: PromiseResolution<T>? {
        if case let .resolved(resolution) = self { return resolution }
        return nil
    }
}

/// Represents a *resolution* (result) of a promise.
public enum PromiseResolution<T> {
    case fulfilled(T), rejected(Error)

    public var value: T? {
        if case let .fulfilled(val) = self { return val }
        return nil
    }

    public var error: Error? {
        if case let .rejected(err) = self { return err }
        return nil
    }
}
