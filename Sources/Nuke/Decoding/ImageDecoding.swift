// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// An image decoder.
///
/// A decoder is a one-shot object created for a single image decoding session.
///
/// The pipeline runs it on its decoding queue (see
/// ``ImagePipeline/Configuration-swift.struct/imageDecodingQueue``), never on
/// its own actor, where every image load in the process would wait for it.
///
/// - note: If you need additional information in the decoder, you can pass
/// anything that you might need from the ``ImageDecodingContext``.
public protocol ImageDecoding: Sendable {
    /// Produces an image from the given image data.
    func decode(_ data: Data) throws -> ImageContainer

    /// Produces an image from the given partially downloaded image data.
    /// This method might be called multiple times during a single decoding
    /// session. When the image download is complete, ``decode(_:)`` method is called.
    ///
    /// - returns: nil by default.
    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer?
}

/// An image decoder that performs decoding asynchronously.
///
/// Use this protocol when decoding needs to call asynchronous APIs. The image
/// pipeline schedules async decoders on its decoding queue and awaits the
/// result without blocking a thread.
@_spi(AsyncImageDecoding)
public protocol AsyncImageDecoding: ImageDecoding {
    /// Asynchronously produces an image from the given image data.
    func decode(_ data: Data) async throws -> ImageContainer
}

extension ImageDecoding {
    /// The default implementation which simply returns `nil` (no progressive
    /// decoding available).
    public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? { nil }
}

extension AsyncImageDecoding {
    /// The default synchronous implementation always throws. The image pipeline
    /// uses the async overload for decoders conforming to ``AsyncImageDecoding``.
    public func decode(_ data: Data) throws -> ImageContainer {
        throw ImageDecodingError.synchronousDecodingUnsupported
    }
}

#if hasAttribute(nonexhaustive)
@nonexhaustive
#endif
public enum ImageDecodingError: Error, CustomStringConvertible, Sendable {
    case unknown
    @_spi(AsyncImageDecoding)
    case synchronousDecodingUnsupported

    public var description: String {
        switch self {
        case .unknown: "Unknown"
        case .synchronousDecodingUnsupported: "Synchronous decoding is not supported"
        }
    }
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
        return makeImageResponse(container, context: context)
    }
}

extension AsyncImageDecoding {
    func decode(_ context: ImageDecodingContext) async throws -> ImageResponse {
        let container: ImageContainer
        if context.isCompleted {
            container = try await decode(context.data)
        } else {
            guard let preview = autoreleasepool(invoking: {
                decodePartiallyDownloadedData(context.data)
            }) else {
                throw ImageDecodingError.unknown
            }
            container = preview
        }
        return makeImageResponse(container, context: context)
    }
}

private func makeImageResponse(_ container: ImageContainer, context: ImageDecodingContext) -> ImageResponse {
    // Marked on every platform: whether to decompress is up to the pipeline
    // (`isDecompressionEnabled`, which is off on macOS by default) and its
    // delegate, so that turning it on works on macOS too.
    if context.request.thumbnail == nil && !container.isPreview {
        ImageDecompression.setDecompressionNeeded(true, for: container.image)
    }
    return ImageResponse(container: container, request: context.request, urlResponse: context.urlResponse, cacheType: context.cacheType)
}
