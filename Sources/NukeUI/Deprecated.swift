// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Combine
import Nuke

// MARK: - Deprecated in Nuke 14

extension FetchImage {
    @available(*, deprecated, message: "Renamed to `ImageTask.Progress`, which `FetchImage/progress` now returns. It's a struct, so a view that observed it with `@ObservedObject` now reads the value directly.")
    public typealias Progress = ImageTask.Progress
}

// MARK: - Removed in Nuke 14
//
// Removed APIs are kept as unavailable stubs that name their replacement: the
// message goes straight into the compiler error. They are deleted two major
// versions after the removal.

extension FetchImage {
    @available(*, unavailable, message: "Removed in Nuke 14. Use `load(_:)` with an async closure, for example `load { try await pipeline.image(for: url) }`.")
    public func load<P: Publisher>(_ publisher: P) where P.Output == ImageResponse {
        fatalError()
    }
}

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
@available(*, unavailable, renamed: "ImageDisplaying", message: "Renamed in Nuke 14. The protocol is no longer `@objc`, so it no longer needs a prefix. Rename `nuke_display(image:data:)` to `display(image:data:)` in your conformances.")
public typealias Nuke_ImageDisplaying = ImageDisplaying
#endif
