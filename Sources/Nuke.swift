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

/// Loads an image into the given target.
///
/// For more info see `loadImage(with:into:)` method of `Manager`.
public func loadImage(with url: URL, into target: Target) {
    Manager.shared.loadImage(with: url, into: target)
}

/// Loads an image into the given target.
///
/// For more info see `loadImage(with:into:)` method of `Manager`.
public func loadImage(with request: Request, into target: Target) {
    Manager.shared.loadImage(with: request, into: target)
}

/// Loads an image and calls the given `handler`. The method itself
/// **doesn't do** anything when the image is loaded - you have full
/// control over how to display it, etc.
///
/// The handler only gets called if the request is still associated with the
/// `target` by the time it's completed. The handler gets called immediately
/// if the image was stored in the memory cache.
///
/// See `loadImage(with:into:)` method for more info.
public func loadImage(with url: URL, into target: AnyObject, handler: @escaping Manager.Handler) {
    Manager.shared.loadImage(with: url, into: target, handler: handler)
}

/// Loads an image and calls the given `handler`. The method itself
/// **doesn't do** anything when the image is loaded - you have full
/// control over how to display it, etc.
///
/// The handler only gets called if the request is still associated with the
/// `target` by the time it's completed. The handler gets called immediately
/// if the image was stored in the memory cache.
///
/// For more info see `loadImage(with:into:handler:)` method of `Manager`.
public func loadImage(with request: Request, into target: AnyObject, handler: @escaping Manager.Handler) {
    Manager.shared.loadImage(with: request, into: target, handler: handler)
}

/// Cancels an outstanding request associated with the target.
public func cancelRequest(for target: AnyObject) {
    Manager.shared.cancelRequest(for: target)
}

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

internal final class Lock {
    var mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)

    init() { pthread_mutex_init(mutex, nil) }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deinitialize()
        mutex.deallocate(capacity: 1)
    }

    /// In critical places it's better to use lock() and unlock() manually
    func sync<T>(_ closure: () -> T) -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return closure()
    }

    func lock() { pthread_mutex_lock(mutex) }
    func unlock() { pthread_mutex_unlock(mutex) }
}
