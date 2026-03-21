// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Fetches original image data.
public protocol DataLoading: Sendable {
    /// - parameter didReceiveData: Can be called multiple times if streaming
    /// is supported.
    /// - parameter completion: Must be called once after all (or none in case
    /// of an error) `didReceiveData` closures have been called.
    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable
}

/// A unit of work that can be cancelled.
public protocol Cancellable: Sendable {
    func cancel()
}

extension DataLoading {
    func loadData(with request: URLRequest) -> AsyncThrowingStream<(Data, URLResponse), Error> {
        AsyncThrowingStream { continuation in
            let cancellable = self.loadData(
                with: request,
                didReceiveData: { data, response in
                    continuation.yield((data, response))
                },
                completion: { error in
                    continuation.finish(throwing: error)
                }
            )
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}
