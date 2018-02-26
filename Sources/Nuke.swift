// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

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


// MARK: - Deprecated

extension Manager {
    @available(*, deprecated, message: "Manager no longer manages cache, it's only responsibility is loading images into targets.")
    convenience init(loader: Loading, cache: Caching? = nil) {
        self.init(loader: loader)
    }
}

@available(*, deprecated, message: "Manager no longer implements Loading protocol. Use Loader.loadImage(with:into:) instead.")
extension Manager: Loading {
    // MARK: Loading Images w/o Targets

    @available(*, deprecated, message: "Manager no longer implements Loading protocol.  loadImage(with:token:completion:) is deprecated. Use Loader methods instead")
    public func loadImage(with request: Request, token: CancellationToken? = nil, completion: @escaping (Result<Image>) -> Void) {
        loader.loadImage(with: request, token: token, completion: completion)
    }

    @available(*, deprecated, message: "Manager no longer implements Loading protocol.  loadImage(with:token:completion:) is deprecated. Use Loader methods instead")
    public func loadImage(with url: URL, token: CancellationToken? = nil, completion: @escaping (Result<Image>) -> Void) {

    }

    @available(*, deprecated, message: "Manager no longer implements Loading protocol.  cachedImage(for:) is deprecated. Use Loader methods instead")
    public func cachedImage(for request: Request) -> Image? {
        return loader.cachedImage(for: request)
    }
}
