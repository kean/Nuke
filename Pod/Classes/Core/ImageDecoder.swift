// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

public protocol ImageDecoding {
    func imageWithData(data: NSData) -> UIImage?
}

public class ImageDecoder: ImageDecoding {
    public init() {}
    public func imageWithData(data: NSData) -> UIImage? {
        #if NUKE_GIF_SUBSPEC_AVAILABLE
            if let image = AnimatedImage(animatedImageData: data) {
                return image
            }
        #endif
        return UIImage(data: data, scale: UIScreen.mainScreen().scale)
    }
}

public class ImageDecoderComposition: ImageDecoding {
    let decoders: [ImageDecoding]
    
    public init(decoders: [ImageDecoding]) {
        self.decoders = decoders
    }
    
    public func imageWithData(data: NSData) -> UIImage? {
        for decoder in self.decoders {
            if let image = decoder.imageWithData(data) {
                return image
            }
        }
        return nil
    }
}
