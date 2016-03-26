// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Represents image response.
public enum ImageResponse {
    /// Task completed successfully.
    case Success(Image, ImageResponseInfo)

    /// Task either failed or was cancelled. See ImageManagerErrorDomain for more info.
    case Failure(ErrorType)
}

/// Convenience methods to access associated values.
public extension ImageResponse {
    /// Returns image if the response was successful.
    public var image: Image? {
        switch self {
        case .Success(let image, _): return image
        case .Failure(_): return nil
        }
    }

    /// Returns error if the response failed.
    public var error: ErrorType? {
        switch self {
        case .Success: return nil
        case .Failure(let error): return error
        }
    }

    /// Returns true if the response was successful.
    public var isSuccess: Bool {
        switch self {
        case .Success: return true
        case .Failure: return false
        }
    }

    // FIXME: Should ImageResponse contain a `fastResponse` property?
    internal func makeFastResponse() -> ImageResponse {
        switch self {
        case .Success(let image, var info):
            info.isFastResponse = true
            return ImageResponse.Success(image, info)
        case .Failure: return self
        }
    }
}

/// Metadata associated with the image response.
public struct ImageResponseInfo {
    /// Returns true if the image was retrieved from memory cache.
    public var isFastResponse: Bool
    
    /// User info returned by the image loader (see ImageLoading protocol).
    public var userInfo: Any?
}
