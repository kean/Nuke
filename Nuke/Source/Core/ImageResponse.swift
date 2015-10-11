// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

public enum ImageResponse {
    case Success(Image, ImageResponseInfo)
    case Failure(ErrorType)

    public var image: Image? {
        switch self {
        case .Success(let image, _): return image
        case .Failure(_): return nil
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
