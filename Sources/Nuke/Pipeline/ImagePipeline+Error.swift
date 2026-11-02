// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImagePipeline {
    /// Represents all possible image pipeline errors.
#if hasAttribute(nonexhaustive)
    @nonexhaustive
#endif
    public enum Error: Swift.Error, CustomStringConvertible, LocalizedError, Sendable {
        // The cases that carry a decoding or processing context are `indirect`:
        // stored inline, the context would make every error – and every `Result`
        // and task event that holds one – about a hundred bytes.

        /// Returned if data is not cached and ``ImageRequest/Options-swift.struct/returnCacheDataDontLoad`` option is specified.
        case dataMissingInCache
        /// Data loader failed to load image data with a wrapped error.
        case dataLoadingFailed(error: Swift.Error)
        /// The pipeline didn't request the URL because it failed recently and
        /// is in cooldown (see ``ImagePipeline/Configuration-swift.struct/failureCooldown``).
        /// The error is the one the failure ended with, which
        /// ``ImagePipeline/Error/dataLoadingError`` returns as well.
        case urlInCooldown(error: Swift.Error)
        /// Data loader returned empty data.
        case dataIsEmpty
        /// No decoder registered for the given data.
        ///
        /// This error can only be thrown if the pipeline has custom decoders.
        /// By default, the pipeline uses ``ImageDecoders/Default`` as a catch-all.
        indirect case decoderNotRegistered(context: ImageDecodingContext)
        /// Decoder failed to produce a final image.
        indirect case decodingFailed(decoder: any ImageDecoding, context: ImageDecodingContext, error: Swift.Error)
        /// Processor failed to produce a final image.
        indirect case processingFailed(processor: any ImageProcessing, context: ImageProcessingContext, error: Swift.Error)
        /// Load image method was called with no image request or no URL.
        case imageRequestMissing
        /// Image pipeline is invalidated and no requests can be made.
        case pipelineInvalidated
        /// The downloaded data exceeded ``ImagePipeline/Configuration/maximumResponseDataSize``.
        case dataDownloadExceededMaximumSize
        /// The image task was cancelled.
        case cancelled
    }
}

extension ImagePipeline.Error {
    /// Returns `true` if the request was cancelled.
    ///
    /// Cancellation is an expected outcome, not a failure: every image view
    /// that scrolls offscreen produces one. Use it to filter cancellations out
    /// of the error UI and the logs.
    ///
    /// ```swift
    /// guard !error.isCancelled else { return }
    /// logger.error("Failed to load image: \(error)")
    /// ```
    public var isCancelled: Bool {
        if case .cancelled = self { true } else { false }
    }

    /// Returns underlying data loading error.
    public var dataLoadingError: Swift.Error? {
        switch self {
        case .dataLoadingFailed(let error), .urlInCooldown(let error):
            return error
        default:
            return nil
        }
    }

    /// The same as ``description``. Without it, `localizedDescription` would
    /// print "The operation couldn't be completed", which says nothing.
    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .dataMissingInCache:
            return "Failed to load data from cache and download is disabled."
        case let .dataLoadingFailed(error):
            return "Failed to load image data. Underlying error: \(error)."
        case let .urlInCooldown(error):
            return "Didn't request the URL because it failed recently and is in cooldown. Underlying error: \(error)."
        case .dataIsEmpty:
            return "Data loader returned empty data."
        case let .decoderNotRegistered(context):
            return "No decoders registered for the downloaded data. \(context.receivedDescription)."
        case let .decodingFailed(decoder, context, error):
            let underlying = error is ImageDecodingError ? "" : " Underlying error: \(error)."
            return "Failed to decode image data using decoder \(decoder).\(underlying) \(context.receivedDescription)."
        case let .processingFailed(processor, context, error):
            let underlying = error is ImageProcessingError ? "" : " Underlying error: \(error)."
            let source = context.request.url.map { " Image URL: \($0.redactedDescription)." } ?? ""
            return "Failed to process the image using processor \(processor).\(underlying)\(source)"
        case .imageRequestMissing:
            return "Load image method was called with no image request or no URL."
        case .pipelineInvalidated:
            return "Image pipeline is invalidated and no requests can be made."
        case .dataDownloadExceededMaximumSize:
            return "The downloaded data exceeded the maximum allowed size."
        case .cancelled:
            return "The image task was cancelled."
        }
    }
}

extension ImageDecodingContext {
    /// What the pipeline received, which is what tells a corrupted image from
    /// the HTML page a server sent back with a `200`: `Received 1.4 KB of
    /// text/html (HTTP 200) from https://example.com/image.jpeg, starting with
    /// "<!DOCTYPE html>"`.
    fileprivate var receivedDescription: String {
        var text = "Received \(Formatter.bytes(data.count))"
        if let type = AssetType(data)?.diagnosticsName ?? urlResponse?.mimeType {
            text += " of \(type)"
        }
        if let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode {
            text += " (HTTP \(statusCode))"
        }
        if let url = request.url {
            text += " from \(url.redactedDescription)"
        }
        return text + ", starting with \(data.preview)"
    }
}

extension Data {
    /// The first bytes of the data: the text, if they are text, and hex
    /// otherwise.
    fileprivate var preview: String {
        let head = prefix(32)
        let isText = !head.isEmpty && head.allSatisfy { (0x20...0x7E).contains($0) || [0x09, 0x0A, 0x0D].contains($0) }
        guard isText, let text = String(bytes: head, encoding: .ascii) else {
            return prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")
        }
        return "\"\(text.split(whereSeparator: \.isWhitespace).joined(separator: " "))\""
    }
}
