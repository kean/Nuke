// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit

public enum ImageContentMode {
    case AspectFill
    case AspectFit
}

public let ImageMaximumSize = CGSizeMake(CGFloat.max, CGFloat.max)

public struct ImageRequest {
    public var URLRequest: NSURLRequest
    
    /** Image target size in pixels.
    */
    public var targetSize: CGSize = ImageMaximumSize
    public var contentMode: ImageContentMode = .AspectFill
    public var shouldDecompressImage = true
    
    /** Filters to be applied to image. Use ImageProcessorComposition to compose multiple filters.
    */
    public var processor: ImageProcessing?
    public var userInfo: Any?
    
    public init(URL: NSURL, targetSize: CGSize = ImageMaximumSize, contentMode: ImageContentMode = .AspectFill) {
        self.URLRequest = NSURLRequest(URL: URL)
        self.targetSize = targetSize
        self.contentMode = contentMode
    }
    
    public init(URLRequest: NSURLRequest, targetSize: CGSize = ImageMaximumSize, contentMode: ImageContentMode = .AspectFill) {
        self.URLRequest = URLRequest
        self.targetSize = targetSize
        self.contentMode = contentMode
    }
}

internal extension ImageRequest {
    var allowsCaching: Bool {
        switch self.URLRequest.cachePolicy {
        case .UseProtocolCachePolicy, .ReturnCacheDataElseLoad, .ReturnCacheDataDontLoad: return true
        default: return false
        }
    }
    
    func isLoadEquivalentToRequest(other: ImageRequest) -> Bool {
        let lhs = self.URLRequest, rhs = other.URLRequest
        return lhs.URL == rhs.URL &&
            lhs.cachePolicy == rhs.cachePolicy &&
            lhs.timeoutInterval == rhs.timeoutInterval &&
            lhs.networkServiceType == rhs.networkServiceType &&
            lhs.allowsCellularAccess == rhs.allowsCellularAccess
    }
    
    func isCacheEquivalentToRequest(other: ImageRequest) -> Bool {
        return self.URLRequest.URL == other.URLRequest.URL
    }
}
