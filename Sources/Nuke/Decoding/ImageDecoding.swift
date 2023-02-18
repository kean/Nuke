// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

/// An image decoder.
///
/// A decoder is a one-shot object created for a single image decoding session.
///
/// - note: If you need additional information in the decoder, you can pass
/// anything that you might need from the ``ImageDecodingContext``.
public protocol ImageDecoding: Sendable {
    /// Return `true` if you want the decoding to be performed on the decoding
    /// queue (see ``ImagePipeline/Configuration-swift.struct/imageDecodingQueue``). If `false`, the decoding will be
    /// performed synchronously on the pipeline operation queue. By default, `true`.
    var isAsynchronous: Bool { get }

    /// Produces an image from the given image data.
    func decode(_ data: Data) throws -> ImageContainer

    /// Produces an image from the given partially downloaded image data.
    /// This method might be called multiple times during a single decoding
    /// session. When the image download is complete, ``decode(_:)`` method is called.
    ///
    /// - returns: nil by default.
    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer?
}

extension ImageDecoding {
    /// Returns `true` by default.
    public var isAsynchronous: Bool { true }

    /// The default implementation which simply returns `nil` (no progressive
    /// decoding available).
    public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? { nil }
}

public enum ImageDecodingError: Error, CustomStringConvertible, Sendable {
    case unknown

    public var description: String { "Unknown" }
}

extension ImageDecoding {
    func decode(_ context: ImageDecodingContext) throws -> ImageResponse {
        let container: ImageContainer = try autoreleasepool {
            if context.isCompleted {
                return try decode(context.data)
            } else {
                if let preview = decodePartiallyDownloadedData(context.data) {
                    return preview
                }
                throw ImageDecodingError.unknown
            }
        }
#if !os(macOS)
        if container.userInfo[.isThumbnailKey] == nil {
            ImageDecompression.setDecompressionNeeded(true, for: container.image)
        }
#endif
        return ImageResponse(container: container, request: context.request, urlResponse: context.urlResponse, cacheType: context.cacheType)
    }
}
