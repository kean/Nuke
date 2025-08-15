// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Fetches original image data.
public protocol DataLoading: Sendable {
    /// Returns data for the given request.
    ///
    /// - returns: Sequence that can be called more than once if streaming
    /// is supported.
    func loadData(for request: URLRequest) -> AsyncThrowingStream<(Data, URLResponse), Swift.Error>
}
