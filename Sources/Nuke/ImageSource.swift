// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A place to load an image from when the source of an ``ImageRequest`` fails.
///
/// See ``ImageRequest/alternatives``.
public struct ImageSource: Sendable {
    let resource: ImageRequest.Resource
    /// Takes the place of ``ImageRequest/imageID``, so the source has its own
    /// entries in the caches and coalesces with the other loads of it.
    let id: String?

    /// A source that loads the image from the given URL.
    ///
    /// - note: The URL is optional as a convenience, like the one of
    /// ``ImageRequest``. With a `nil` URL, the source fails with
    /// `URLError(.badURL)`, and the task moves on to the next one.
    public static func url(_ url: URL?) -> ImageSource {
        ImageSource(resource: .url(url), id: url?.absoluteString)
    }

    /// A source that loads the image with the given `URLRequest`.
    public static func urlRequest(_ urlRequest: URLRequest) -> ImageSource {
        ImageSource(resource: .urlRequest(urlRequest), id: urlRequest.url?.absoluteString)
    }

    /// A source that fetches the image data with the given async function.
    ///
    /// - parameters:
    ///   - id: Uniquely identifies the fetched image.
    ///   - fetch: An async function to be used to fetch image data.
    public static func data(id: String, _ fetch: @Sendable @escaping () async throws -> Data) -> ImageSource {
        ImageSource(resource: .data(fetch: fetch), id: id)
    }

    /// A source that fetches the image with the given async function, such as
    /// one that returns a placeholder from the app's assets.
    ///
    /// - parameters:
    ///   - id: Uniquely identifies the fetched image.
    ///   - fetch: An async function returning an ``ImageContainer``.
    public static func image(id: String, _ fetch: @Sendable @escaping () async throws -> ImageContainer) -> ImageSource {
        ImageSource(resource: .image(fetch: fetch), id: id)
    }
}
