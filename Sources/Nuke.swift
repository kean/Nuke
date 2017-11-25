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
