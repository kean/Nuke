// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Fetches original image data.
public protocol DataLoading: Sendable {
    /// Loads data for the given request.
    func data(for request: URLRequest) -> AsyncThrowingStream<DataTaskSequenceElement, Error>
}

public enum DataTaskSequenceElement {
    case respone(URLResponse)
    case data(Data)
}

public protocol DataLoadingDelegate: AnyObject {
    func dataLoaderDidRecieveResponse(_ urlResponse: URLResponse)
    func dataLoaderDidRecieveData(_ data: Data)
    func dataLoaderDidCompleteWithError(error: Error?)
}

/// A unit of work that can be cancelled.
public protocol Cancellable: AnyObject, Sendable {
    func cancel()
}
