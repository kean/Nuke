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

/// Loads an image into the given target and calls the given `handler`.
///
/// For more info see `loadImage(with:into:handler:)` method of `Manager`.
public func loadImage(with request: Request, into target: AnyObject, handler: @escaping Manager.Handler) {
    Manager.shared.loadImage(with: request, into: target, handler: handler)
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
