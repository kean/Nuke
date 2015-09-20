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
    public var URL: NSURL
    
    /** Image target size in pixels.
    */
    public var targetSize: CGSize = ImageMaximumSize
    public var contentMode: ImageContentMode = .AspectFill
    public var shouldDecompressImage = true
    
    /** Filters to be applied to image. Use ImageProcessorComposition to compose multiple filters.
    */
    public var processor: ImageProcessing?
    public var userInfo: Any?
    
    public init(URL: NSURL, targetSize: CGSize, contentMode: ImageContentMode) {
        self.URL = URL
        self.targetSize = targetSize
        self.contentMode = contentMode
    }
    
    public init(URL: NSURL) {
        self.URL = URL
    }
}
