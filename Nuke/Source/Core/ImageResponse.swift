// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit

public enum ImageResponse {
    case Success(UIImage, ImageResponseInfo)
    case Failure(ErrorType)
    
    public var image: UIImage? {
        get {
            switch self {
            case let .Success(image, _): return image
            case .Failure(_): return nil
            }
        }
    }
}

public class ImageResponseInfo {
    public let fastResponse: Bool
    public let userInfo: Any?
    
    public init(fastResponse: Bool, userInfo: Any? = nil) {
        self.fastResponse = fastResponse
        self.userInfo = userInfo
    }
}
