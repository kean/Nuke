// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Combine
import Nuke

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
