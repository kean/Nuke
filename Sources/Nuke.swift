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

/// Loads an image for the given `URL` using shared `Loader`.
public func loadImage(with url: URL, token: CancellationToken? = nil) -> Promise<Image> {
    return Loader.shared.loadImage(with: url, token: token)
}

/// Creates a task with the given `Request` using shared `Loader`.
/// - parameter options: `Options()` be default.
public func loadImage(with request: Request, token: CancellationToken? = nil) -> Promise<Image> {
    return Loader.shared.loadImage(with: request, token: token)
}

// MARK: - Loading Extensions

public extension Loading {
    /// Creates a task with with given request.
    func loadImage(with url: URL, token: CancellationToken? = nil) -> Promise<Image> {
        return loadImage(with: Request(url: url), token: token)
    }
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
