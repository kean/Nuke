// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A promise is an object that represents an asynchronous task. Use `then(...)` to
/// get the result of the promise. Use `catch(...)` to catch errors.
///
/// Promises start in a *pending* state and *resolve* with a value to become
/// *fulfilled* or an `Error` to become *rejected*.
///
/// A notable `Promise` feature is that it bubbles up errors. It allows you to
/// catch all errors returned by a chain of promises with a single `catch(...)`.
public final class Promise<T> {
    // Promise is built into Nuke to avoid fetching external dependencies.

    private var state: PromiseState<T> = .pending(PromiseHandlers<T>())
    private let lock = Lock()

    /// Creates a new, pending promise.
    ///
    /// ```
    /// func loadData(url: URL) -> Promise<Data> {
    ///     return Promise<Data> { fulfill, reject in
    ///         URLSession.shared.dataTask(with: url) { data, _, error in
    ///             if let data = data {
    ///                 fulfill(data)
    ///             } else {
    ///                 reject(error ?? unknownError)
    ///             }
    ///         }.resume()
    ///     }
    /// }
    /// ```
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
    public func completion(on queue: DispatchQueue = .main, _ closure: @escaping (PromiseResolution<T>) -> Void) {
        let completion: (PromiseResolution<T>) -> Void = { resolution in
            queue.async { closure(resolution) }
        }
        lock.lock()
        switch state {
        case let .pending(handlers): handlers.objects.append(completion)
        case let .resolved(resolution): completion(resolution)
        }
        lock.unlock()
    }
}

public extension Promise {

    /// The provided closure executes asynchronously when the promise fulfills
    /// with a value.
    ///
    /// - parameter on: A queue on which the closure is executed. `.main` by default.
    /// - returns: self
    @discardableResult public func then(on queue: DispatchQueue = .main, _ closure: @escaping (T) -> Void) -> Promise {
        return then(on: queue, fulfilment: closure, rejection: nil)
    }

    /// The provided closure executes asynchronously when the promise fulfills
    /// with a value.
    ///
    /// - parameter on: A queue on which the closure is executed. `.main` by default.
    /// queue by default.
    /// - returns: A promise fulfilled with a value returns by the closure.
    public func then<U>(on queue: DispatchQueue = .main, _ closure: @escaping (T) -> U) -> Promise<U> {
        return then(on: queue) { Promise<U>(value: closure($0)) }
    }

    /// The provided closure executes asynchronously when the promise fulfills
    /// with a value.
    ///
    /// - parameter on: A queue on which the closure is executed. `.main` by default.
    /// - returns: A promise that resolves with the resolution of the promise
    /// returned by the given closure. Allows to chain promises.
    public func then<U>(on queue: DispatchQueue = .main, _ closure: @escaping (T) -> Promise<U>) -> Promise<U> {
        return Promise<U>() { fulfill, reject in
            then(
                on: queue,
                fulfilment: {
                    closure($0).then(
                        fulfilment: { fulfill($0) },
                        rejection: { reject($0) })
                },
                rejection: { reject($0) }) // bubble up error
        }
    }

    /// The provided closure executes asynchronously when the promise is
    /// rejected with an error.
    ///
    /// - parameter on: A queue on which the closure is executed. `.main` by default.
    @discardableResult public func `catch`(on queue: DispatchQueue = .main, _ closure: @escaping (Error) -> Void) {
        then(on: queue, fulfilment: nil, rejection: closure)
    }

    /// The provided closure executes asynchronously when the promise is rejected.
    /// Unlike `catch` `recover` allows you to continue the chain of promises
    /// by recovering from an error with a new promise.
    ///
    /// - parameter on: A queue on which the closure is executed. `.main` by default.
    public func recover(on queue: DispatchQueue = .main, _ closure: @escaping (Error) -> Promise) -> Promise {
        return Promise() { fulfill, reject in
            then(
                on: queue,
                fulfilment: { fulfill($0) }, // bubble up value
                rejection: {
                    closure($0).then(
                        fulfilment: { fulfill($0) },
                        rejection: { reject($0) })
            })
        }
    }

    /// The provided closure executes asynchronously when the promise resolves.
    ///
    /// - parameter on: A queue on which the closure is executed. `.main` by default.
    @discardableResult public func then(on queue: DispatchQueue = .main, fulfilment: ((T) -> Void)?, rejection: ((Error) -> Void)?) -> Promise {
        completion(on: queue) { resolution in
            switch resolution {
            case let .fulfilled(val): fulfilment?(val)
            case let .rejected(err): rejection?(err)
            }
        }
        return self
    }
}

// FIXME: make nested type when compiler adds support for it
private final class PromiseHandlers<T> {
    var objects = [(PromiseResolution<T>) -> Void]()
}

private enum PromiseState<T> {
    case pending(PromiseHandlers<T>), resolved(PromiseResolution<T>)
}

public enum PromiseResolution<T> {
    case fulfilled(T), rejected(Error)
}
