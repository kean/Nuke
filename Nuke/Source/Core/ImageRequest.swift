// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation
#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

public enum ImageContentMode {
    case AspectFill
    case AspectFit
}

/* Size to pass when requesting the original image available for a request (image won't be resized).
*/
public let ImageMaximumSize = CGSizeMake(CGFloat.max, CGFloat.max)

/** Encapsulates image request parameters.
*/
public struct ImageRequest {
    public var URLRequest: NSURLRequest
    
    /** Target size in pixels. Default value is ImageMaximumSize.
    */
    public var targetSize: CGSize = ImageMaximumSize
    
    /** Content mode. Default value is .AspectFill.
    */
    public var contentMode: ImageContentMode = .AspectFill
    
    /** Default value is true.
    */
    public var shouldDecompressImage = true
    
    /** Filter to be applied to the image. Use ImageProcessorComposition to compose multiple filters.
    */
    public var processor: ImageProcessing?
    public var userInfo: Any?
    
    /** Initializes request with a URL.
     - parameter targetSize: Default value is ImageMaximumSize
     - parameter contentMode: Default value is .AspectFill
    */
    public init(URL: NSURL, targetSize: CGSize = ImageMaximumSize, contentMode: ImageContentMode = .AspectFill) {
        self.URLRequest = NSURLRequest(URL: URL)
        self.targetSize = targetSize
        self.contentMode = contentMode
    }
    
    /** Initializes request with a URL request.
     - parameter targetSize: Default value is ImageMaximumSize
     - parameter contentMode: Default value is .AspectFill
    */
    public init(URLRequest: NSURLRequest, targetSize: CGSize = ImageMaximumSize, contentMode: ImageContentMode = .AspectFill) {
        self.URLRequest = URLRequest
        self.targetSize = targetSize
        self.contentMode = contentMode
    }
}

public extension ImageRequest {
    public var allowsCaching: Bool {
        switch self.URLRequest.cachePolicy {
        case .UseProtocolCachePolicy, .ReturnCacheDataElseLoad, .ReturnCacheDataDontLoad: return true
        default: return false
        }
    }
    
    public func isLoadEquivalentToRequest(other: ImageRequest) -> Bool {
        let lhs = self.URLRequest, rhs = other.URLRequest
        return lhs.URL == rhs.URL &&
            lhs.cachePolicy == rhs.cachePolicy &&
            lhs.timeoutInterval == rhs.timeoutInterval &&
            lhs.networkServiceType == rhs.networkServiceType &&
            lhs.allowsCellularAccess == rhs.allowsCellularAccess
    }
    
    public func isCacheEquivalentToRequest(other: ImageRequest) -> Bool {
        return self.URLRequest.URL == other.URLRequest.URL
    }
}
