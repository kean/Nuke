// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

// MARK: - Removed in Nuke 14
//
// Removed APIs are kept as unavailable stubs that name their replacement: the
// message goes straight into the compiler error. They are deleted two major
// versions after the removal.

/// - warning: Renamed to ``ImageDisplaying``.
@available(*, unavailable, renamed: "ImageDisplaying")
public typealias Nuke_ImageDisplaying = ImageDisplaying

extension ImageDisplaying {
    // Stubs the call, which is all a stub can do: an `override` of it in a
    // `UIImageView` subclass already fails with "does not override".
    @available(*, unavailable, message: "Removed in Nuke 14. Use `nuke_display(_:)`, which takes the `ImageContainer`: `image` is `container?.image`, and `data` is `container?.data`.")
    public func nuke_display(image: PlatformImage?, data: Data? = nil) { fatalError("Unavailable") }
}

#endif
