// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Fetches original image data.
public protocol DataLoading: Sendable {
    /// Loads data for the given request.
    ///
    /// - Returns: A tuple of an `AsyncThrowingStream` delivering data chunks
    ///   and the initial `URLResponse`.
    func loadData(with request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse)
}
