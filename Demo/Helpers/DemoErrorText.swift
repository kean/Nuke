// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

extension ImagePipeline.Error {
    /// The error in a few words, for a line under an image: the loader's error
    /// for a failed download – "URLError -1001", "status 404" – and the name of
    /// the case otherwise, "decodingFailed".
    ///
    /// `description` is no good there: for a failed download it prints the
    /// whole `NSError` it wraps, the failing URL included, which runs to ten
    /// lines.
    var demoSummary: String {
        dataLoadingError.flatMap(demoLoaderErrorSummary) ?? demoCaseName
    }

    /// The error in a sentence an app could show: what the loader said about
    /// a failed download, "The request timed out.", and the pipeline's own
    /// description otherwise.
    var demoMessage: String {
        dataLoadingError.map(demoLoaderErrorMessage) ?? description
    }

    /// The name of the case, without its payload.
    var demoCaseName: String {
        switch self {
        case .dataMissingInCache: "dataMissingInCache"
        case .dataLoadingFailed: "dataLoadingFailed"
        case .dataIsEmpty: "dataIsEmpty"
        case .decoderNotRegistered: "decoderNotRegistered"
        case .decodingFailed: "decodingFailed"
        case .processingFailed: "processingFailed"
        case .imageRequestMissing: "imageRequestMissing"
        case .pipelineInvalidated: "pipelineInvalidated"
        case .dataDownloadExceededMaximumSize: "dataDownloadExceededMaximumSize"
        case .cancelled: "cancelled"
        @unknown default: "unknown"
        }
    }
}

/// A data loader's error in a few words, "URLError -1001" or "status 404", or
/// `nil` for an error that has no short form.
func demoLoaderErrorSummary(_ error: any Error) -> String? {
    if let error = error as? URLError {
        return "URLError \(error.code.rawValue)"
    }
    if case .statusCodeUnacceptable(let code)? = error as? DataLoader.Error {
        return "status \(code)"
    }
    return nil
}

/// A data loader's error in a sentence an app could show: "The request timed
/// out."
func demoLoaderErrorMessage(_ error: any Error) -> String {
    (error as? URLError)?.localizedDescription ?? String(describing: error)
}
