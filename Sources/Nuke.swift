// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

#if os(OSX)
    import AppKit.NSImage
    /// Alias for NSImage
    public typealias Image = NSImage
#else
    import UIKit.UIImage
    /// Alias for UIImage
    public typealias Image = UIImage
#endif

internal let domain = "com.github.kean.Nuke"

// MARK: - Loading Images

/// Loads an image for the given `URL` using shared `Loader`.
public func loadImage(with url: URL, token: CancellationToken? = nil) -> Promise<Image> {
    return Loader.shared.loadImage(with: url, token: token)
}

/// Creates a task with the given `Request` using shared `Loader`.
/// - parameter options: `Options()` be default.
public func loadImage(with request: Request, token: CancellationToken? = nil) -> Promise<Image> {
    return Loader.shared.loadImage(with: request, token: token)
}

// MARK: - Loading Images into Views

public func loadImage(with url: URL, into target: Target) {
    Manager.shared.loadImage(with: url, into: target)
}

public func loadImage(with request: Request, into target: Target, handler: Manager.Handler? = nil) {
    Manager.shared.loadImage(with: request, into: target, handler: handler)
}

// MARK: - Shared

public extension Manager {
    public static var shared = Manager(loader: Loader.shared, cache: Cache.shared)
}

public extension Loader {
    /// Shared `Loader` instance.
    ///
    /// Shared loader is created with `DataLoader()`, `DataDecoder()`. 
    /// Loader is wrapped into `Deduplicator`.
    public static var shared: Loading = {
        return Loader(loader: DataLoader(), decoder: DataDecoder(), cache: Cache.shared)
    }()
}

public extension Cache {
    public static var shared = Cache()
}
