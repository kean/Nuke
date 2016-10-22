// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

#if os(macOS)
    import AppKit.NSImage
    /// Alias for NSImage
    public typealias Image = NSImage
#else
    import UIKit.UIImage
    /// Alias for UIImage
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
/// `target` by the time it's completed.
///
/// See `loadImage(with:into:)` method for more info.
public func loadImage(with url: URL, into target: AnyObject, handler: @escaping Manager.Handler) {
    Manager.shared.loadImage(with: url, into: target, handler: handler)
}

/// Loads an image and calls the given `handler`.
///
/// For more info see `loadImage(with:into:handler:)` method of `Manager`.
public func loadImage(with request: Request, into target: AnyObject, handler: @escaping Manager.Handler) {
    Manager.shared.loadImage(with: request, into: target, handler: handler)
}

/// Cancels an outstanding request associated with the target.
public func cancelRequest(for target: AnyObject) {
    Manager.shared.cancelRequest(for: target)
}

public extension Manager {
    /// Shared `Manager` instance.
    ///
    /// Shared manager is created with `Loader.shared` and `Cache.shared`.
    public static var shared = Manager(loader: Loader.shared, cache: Cache.shared)
}

public extension Loader {
    /// Shared `Loading` object.
    ///
    /// Shared loader is created with `DataLoader()`, `DataDecoder()` and
    // `Cache.shared`. The resulting loader is wrapped in a `Deduplicator`.
    public static var shared: Loading = Deduplicator(loader: Loader(loader: DataLoader(), decoder: DataDecoder(), cache: Cache.shared))
}

public extension Cache {
    /// Shared `Cache` instance.
    public static var shared = Cache()
}

internal final class Lock {
    var mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    
    init() {
        pthread_mutex_init(mutex, nil)
    }
    
    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deinitialize()
        mutex.deallocate(capacity: 1)
    }
    
    /// In critical places it's better to use lock() and unlock() manually
    func sync<T>(_ closure: (Void) -> T) -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return closure()
    }
    
    func lock() { pthread_mutex_lock(mutex) }
    func unlock() { pthread_mutex_unlock(mutex) }
}
