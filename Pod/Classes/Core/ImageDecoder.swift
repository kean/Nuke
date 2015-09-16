// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

public protocol ImageDecoding {
    func imageWithData(data: NSData) -> UIImage?
}


public class ImageDecoder: ImageDecoding {
    public func imageWithData(data: NSData) -> UIImage? {
        return UIImage(data: data, scale: UIScreen.mainScreen().scale)
    }
}
