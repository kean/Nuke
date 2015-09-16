// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

public enum ImageResponse {
    case Success(UIImage, ImageResponseInfo)
    case Failure(NSError)
    
    public var image: UIImage? {
        get {
            switch self {
            case let .Success(image, _): return image
            case .Failure(_): return nil;
            }
        }
    }
}

public class ImageResponseInfo {
    public let fastResponse: Bool
    public let info: NSDictionary?
    
    public init(info: NSDictionary?, fastResponse: Bool) {
        self.info = info
        self.fastResponse = fastResponse
    }
}
