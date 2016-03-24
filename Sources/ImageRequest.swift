// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

/// An option for how to resize the image to the target size.
public enum ImageContentMode {
    /// Scales the image so that it completely fills the target size. Maintains image aspect ratio. Images are not clipped.
    case AspectFill
    
    /// Scales the image so that its larger dimension fits the target size. Maintains image aspect ratio.
    case AspectFit
}

/// Defines constants that can be used to modify the way ImageManager interacts with the memory cache.
public enum ImageRequestMemoryCachePolicy {
    /// Return memory cached image corresponding the request. If there is no existing image in the memory cache, the image manager continues with the request.
    case ReturnCachedImageElseLoad
    
    /// Reload using ignoring memory cached images. Doesn't affect on-disk caching.
    case ReloadIgnoringCachedImage
}

/// Size to pass when requesting the original image available for a request (image won't be resized).
public let ImageMaximumSize = CGSizeMake(CGFloat.max, CGFloat.max)

/// Encapsulates image request parameters.
public struct ImageRequest {
    /// The URL request that the image request was created with.
    public var URLRequest: NSURLRequest
    
    /**
     Target size in pixels. The loaded image is resized to the given target size respecting the given content mode and maintaining aspect ratio. Default value is ImageMaximumSize.
     
     Default ImageLoader implementation decompresses the loaded image using instance of ImageDecompressor class which is created with a targetSize and contentMode from the ImageRequest. See ImageDecompressor class for more info.
     */
    public var targetSize: CGSize = ImageMaximumSize
    
    /// An option for how to resize the image to the target size. Default value is .AspectFill. See ImageContentMode enum for more info.
    public var contentMode: ImageContentMode = .AspectFill
    
    /// Specifies whether loaded image should be stored into memory cache. Default value is true.
    public var memoryCacheStorageAllowed = true
    
    /// The request memory cachce policy. Default value is .ReturnCachedImageElseLoad.
    public var memoryCachePolicy = ImageRequestMemoryCachePolicy.ReturnCachedImageElseLoad
    
    /// Default value is true.
    public var shouldDecompressImage = true
    
    /// Filter to be applied to the image. Use ImageProcessorComposition to compose multiple filters.
    public var processor: ImageProcessing?
    
    #if !os(OSX)
    /// The relative priority at which you’d like a host to handle the task. The priority is used when creating an underlying NSURLSessionTask.
    public var priority: Float?
    #endif
    
    /// Allows users to pass some custom info alongside the request.
    public var userInfo: Any?
    
    /**
     Initializes request with a URL.
     
     - parameter targetSize: Target size in pixels. Default value is ImageMaximumSize. See targetSize property for more info.
     - parameter contentMode: An option for how to resize the image to the target size. Default value is .AspectFill. See ImageContentMode enum for more info.
     */
    public init(URL: NSURL, targetSize: CGSize = ImageMaximumSize, contentMode: ImageContentMode = .AspectFill) {
        self.URLRequest = NSURLRequest(URL: URL)
        self.targetSize = targetSize
        self.contentMode = contentMode
    }
    
    /**
     Initializes request with a URL request.
     
     - parameter targetSize: Target size in pixels. Default value is ImageMaximumSize. See targetSize property for more info.
     - parameter contentMode: An option for how to resize the image to the target size. Default value is .AspectFill. See ImageContentMode enum for more info.
     */
    public init(URLRequest: NSURLRequest, targetSize: CGSize = ImageMaximumSize, contentMode: ImageContentMode = .AspectFill) {
        self.URLRequest = URLRequest
        self.targetSize = targetSize
        self.contentMode = contentMode
    }
}
