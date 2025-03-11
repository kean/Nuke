// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Resumable data support. For more info see:
/// - https://developer.apple.com/library/content/qa/qa1761/_index.html
struct ResumableData: Sendable {
    let data: Data
    let validator: String // Either Last-Modified or ETag

    init?(response: URLResponse, data: Data) {
        // Check if "Accept-Ranges" is present and the response is valid.
        guard !data.isEmpty,
            let response = response as? HTTPURLResponse,
            data.count < response.expectedContentLength,
            response.statusCode == 200 /* OK */ || response.statusCode == 206, /* Partial Content */
            let acceptRanges = response.allHeaderFields["Accept-Ranges"] as? String,
            acceptRanges.lowercased() == "bytes",
            let validator = ResumableData._validator(from: response) else {
                return nil
        }

        // NOTE: https://developer.apple.com/documentation/foundation/httpurlresponse/1417930-allheaderfields
        // HTTP headers are case insensitive. To simplify your code, certain
        // header field names are canonicalized into their standard form.
        // For example, if the server sends a content-length header,
        // it is automatically adjusted to be Content-Length.

        self.data = data; self.validator = validator
    }

    private static func _validator(from response: HTTPURLResponse) -> String? {
        if let entityTag = response.allHeaderFields["ETag"] as? String {
            return entityTag // Prefer ETag
        }
        // There seems to be a bug with ETag where HTTPURLResponse would canonicalize
        // it to Etag instead of ETag
        // https://bugs.swift.org/browse/SR-2429
        if let entityTag = response.allHeaderFields["Etag"] as? String {
            return entityTag // Prefer ETag
        }
        if let lastModified = response.allHeaderFields["Last-Modified"] as? String {
            return lastModified
        }
        return nil
    }

    func resume(request: inout URLRequest) {
        var headers = request.allHTTPHeaderFields ?? [:]
        // "bytes=1000-" means bytes from 1000 up to the end (inclusive)
        headers["Range"] = "bytes=\(data.count)-"
        headers["If-Range"] = validator
        request.allHTTPHeaderFields = headers
    }

    // Check if the server decided to resume the response.
    static func isResumedResponse(_ response: URLResponse) -> Bool {
        // "206 Partial Content" (server accepted "If-Range")
        (response as? HTTPURLResponse)?.statusCode == 206
    }
}

/// Shared cache, uses the same memory pool across multiple pipelines.
final class ResumableDataStorage: @unchecked Sendable {
    static let shared = ResumableDataStorage()

    private let lock = NSLock()
    private var namespaces = Set<UUID>()

    private var cache: Cache<Key, ResumableData>?

    // MARK: Registration

    func register(_ namespace: UUID) {
        lock.lock()
        defer { lock.unlock() }

        if namespaces.isEmpty {
            // 32 MB
            cache = Cache(costLimit: 32000000, countLimit: 100)
        }
        namespaces.insert(namespace)
    }

    func unregister(_ namespace: UUID) {
        lock.lock()
        defer { lock.unlock() }

        namespaces.remove(namespace)
        if namespaces.isEmpty {
            cache = nil // Deallocate storage
        }
    }

    func removeAllResponses() {
        lock.lock()
        defer { lock.unlock() }

        cache?.removeAllCachedValues()
    }

    // MARK: Storage

    func removeResumableData(for request: ImageRequest, namespace: UUID) -> ResumableData? {
        lock.lock()
        defer { lock.unlock() }

        guard let key = Key(request: request, namespace: namespace) else { return nil }
        return cache?.removeValue(forKey: key)
    }

    func storeResumableData(_ data: ResumableData, for request: ImageRequest, namespace: UUID) {
        lock.lock()
        defer { lock.unlock() }

        guard let key = Key(request: request, namespace: namespace) else { return }
        cache?.set(data, forKey: key, cost: data.data.count)
    }

    private struct Key: Hashable {
        let namespace: UUID
        let imageId: String

        init?(request: ImageRequest, namespace: UUID) {
            guard let imageId = request.imageId else {
                return nil
            }
            self.namespace = namespace
            self.imageId = imageId
        }
    }
}
