// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImagePipeline {
    // Deprecated in Nuke 12.7
    @available(*, deprecated, message: "Plesae the variant variant that accepts `ImageRequest` as a parameter")
    @discardableResult public func loadData(with url: URL, completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void) -> ImageTask {
        loadData(with: ImageRequest(url: url), queue: nil, progress: nil, completion: completion)
    }

    // Deprecated in Nuke 12.7
    @available(*, deprecated, message: "Plesae the variant that accepts `ImageRequest` as a parameter")
    @discardableResult public func data(for url: URL) async throws -> (Data, URLResponse?) {
        try await data(for: ImageRequest(url: url))
    }
}
