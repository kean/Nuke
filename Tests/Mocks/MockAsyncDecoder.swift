// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
@_spi(AsyncImageDecoding) import Nuke

/// An ``AsyncImageDecoding`` decoder that decodes with the given closures.
final class MockAsyncDecoder: AsyncImageDecoding, Sendable {
    private let _decode: @Sendable (Data) async throws -> ImageContainer
    private let _decodePreview: (@Sendable (Data) -> ImageContainer?)?

    /// - parameters:
    ///   - decode: Decodes the final image. By default, it suspends, then
    ///     returns an empty image.
    ///   - decodePreview: Decodes the partial data. When `nil` (the default),
    ///     the decoder doesn't support previews.
    init(
        decode: @escaping @Sendable (Data) async throws -> ImageContainer = { _ in
            await Task.yield()
            return ImageContainer(image: PlatformImage())
        },
        decodePreview: (@Sendable (Data) -> ImageContainer?)? = nil
    ) {
        self._decode = decode
        self._decodePreview = decodePreview
    }

    func decode(_ data: Data) async throws -> ImageContainer {
        try await _decode(data)
    }

    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        _decodePreview?(data)
    }
}
