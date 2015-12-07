// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

/** Represents image response.
 */
public enum ImageResponse {
    case Success(Image, ImageResponseInfo)
    case Failure(ErrorType)
}

/** Convenience methods to access associated values.
 */
public extension ImageResponse {
    public var image: Image? {
        switch self {
        case .Success(let image, _): return image
        case .Failure(_): return nil
        }
    }
    
    public var info: ImageResponseInfo? {
        switch self {
        case .Success(_, let info): return info
        case .Failure(_): return nil
        }
    }
    
    public var error: ErrorType? {
        switch self {
        case .Success: return nil
        case .Failure(let error): return error
        }
    }
    
    public var success: Bool {
        switch self {
        case .Success: return true
        case .Failure: return false
        }
    }
}

/** Metadata associated with the image response.
 */
public class ImageResponseInfo {
    
    /** Returns true if the image was retrieved from memory cache.
     */
    public let fastResponse: Bool
    
    /** User info returned by the image loader (see ImageLoading protocol).
     */
    public let userInfo: Any?
    
    public init(fastResponse: Bool, userInfo: Any? = nil) {
        self.fastResponse = fastResponse
        self.userInfo = userInfo
    }
}
