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

/// Asynchronously fulfills the request into the given target.
///
/// For more info see `loadImage(with:into:)` method of `Manager` class.
public func loadImage(with url: URL, into target: Target) {
    Manager.shared.loadImage(with: url, into: target)
}

/// Asynchronously fulfills the request into the given target.
///
/// For more info see `loadImage(with:into:)` method of `Manager` class.
public func loadImage(with request: Request, into target: Target) {
    Manager.shared.loadImage(with: request, into: target)
}

public extension Manager {
    /// Shared `Manager` instance.
    ///
    /// Shared manager is created with `Loader.shared` and `Cache.shared`.
    public static var shared = Manager(loader: Loader.shared, cache: Cache.shared)
}

public extension Loader {
    /// Shared `Loader` instance.
    ///
    /// Shared loader is created with `DataLoader()`, `DataDecoder()` and `Cache.shared`.
    public static var shared = Loader(loader: DataLoader(), decoder: DataDecoder(), cache: Cache.shared)
}

public extension Cache {
    /// Shared `Cache` instance.
    public static var shared = Cache()
}
