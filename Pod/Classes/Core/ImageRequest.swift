// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

public struct ImageRequest {
    public var URL: NSURL
    public var targetSize: CGSize = ImageMaximumSize // Target size in pixels
    public var contentMode: ImageContentMode = .AspectFill
    public var userInfo: AnyObject?
    
    public init(URL: NSURL, targetSize: CGSize, contentMode: ImageContentMode) {
        self.URL = URL
        self.targetSize = targetSize
        self.contentMode = contentMode
    }
    
    public init(URL: NSURL) {
        self.URL = URL
    }
}
