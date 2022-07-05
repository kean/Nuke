// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImagePipeline {
    /// Represents all possible image pipeline errors.
    public enum Error: Swift.Error, CustomStringConvertible, @unchecked Sendable {
        /// Returned if data not cached and ``ImageRequest/Options-swift.struct/returnCacheDataDontLoad`` option is specified.
        case dataMissingInCache
        /// Data loader failed to load image data with a wrapped error.
        case dataLoadingFailed(error: Swift.Error)
        /// Data loader returned empty data.
        case dataIsEmpty
        /// No decoder registered for the given data.
        ///
        /// This error can only be thrown if the pipeline has custom decoders.
        /// By default, the pipeline uses ``ImageDecoders/Default`` as a catch-all.
        case decoderNotRegistered(context: ImageDecodingContext)
        /// Decoder failed to produce a final image.
        case decodingFailed(decoder: any ImageDecoding, context: ImageDecodingContext, error: Swift.Error)
        /// Processor failed to produce a final image.
        case processingFailed(processor: any ImageProcessing, context: ImageProcessingContext, error: Swift.Error)
        /// Load image method was called with no image request.
        case imageRequestMissing
        /// Image pipeline is invalidated and no requests can be made.
        case pipelineInvalidated
    }
}

extension ImagePipeline.Error {
    /// Returns underlying data loading error.
    public var dataLoadingError: Swift.Error? {
        switch self {
        case .dataLoadingFailed(let error):
            return error
        default:
            return nil
        }
    }

    public var description: String {
        switch self {
        case .dataMissingInCache:
            return "Failed to load data from cache and download is disabled."
        case let .dataLoadingFailed(error):
            return "Failed to load image data. Underlying error: \(error)."
        case .dataIsEmpty:
            return "Data loader returned empty data."
        case .decoderNotRegistered:
            return "No decoders registered for the downloaded data."
        case let .decodingFailed(decoder, _, error):
            let underlying = error is ImageDecodingError ? "" : " Underlying error: \(error)."
            return "Failed to decode image data using decoder \(decoder).\(underlying)"
        case let .processingFailed(processor, _, error):
            let underlying = error is ImageProcessingError ? "" : " Underlying error: \(error)."
            return "Failed to process the image using processor \(processor).\(underlying)"
        case .imageRequestMissing:
            return "Load image method was called with no image request or no URL."
        case .pipelineInvalidated:
            return "Image pipeline is invalidated and no requests can be made."
        }
    }
}
