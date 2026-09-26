// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os
import Nuke

/// Intercepts the URL requests with
/// ``ImagePipeline/Delegate-swift.protocol/willLoadData(for:urlRequest:pipeline:)``
/// and records them.
final class MockWillLoadDataDelegate: ImagePipeline.Delegate, Sendable {
    /// The URL requests the pipeline was about to load, in order.
    var requests: [URLRequest] { _requests.withLock { $0 } }

    private let handler: @Sendable (URLRequest) async throws -> URLRequest
    private let _requests = OSAllocatedUnfairLock<[URLRequest]>(initialState: [])

    /// - parameter handler: Returns the URL request to load, or throws to
    ///   fail the task. Returns the request unchanged by default.
    init(handler: @escaping @Sendable (URLRequest) async throws -> URLRequest = { $0 }) {
        self.handler = handler
    }

    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        _requests.withLock { $0.append(urlRequest) }
        return try await handler(urlRequest)
    }
}
