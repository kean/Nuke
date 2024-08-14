// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Fetches original image data.
public protocol DataLoading: Sendable {
    /// - parameter didReceiveData: Can be called multiple times if streaming
    /// is supported.
    /// - parameter completion: Must be called once after all (or none in case
    /// of an error) `didReceiveData` closures have been called.
    func loadData(with request: URLRequest,
                  didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                  completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable
}

/// A unit of work that can be cancelled.
public protocol Cancellable: AnyObject, Sendable {
    func cancel()
}
