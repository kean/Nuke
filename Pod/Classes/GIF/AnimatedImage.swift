// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit
import FLAnimatedImage

public class AnimatedImage: UIImage {
    public let animatedImage: FLAnimatedImage?
    
    public init(animatedImage: FLAnimatedImage, posterImage: CGImageRef, posterImageScale: CGFloat, posterImageOrientation: UIImageOrientation) {
        self.animatedImage = animatedImage
        super.init(CGImage: posterImage, scale: posterImageScale, orientation: posterImageOrientation)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        self.animatedImage = nil
        super.init(coder: aDecoder) // makes me sad every time
    }
}

public class AnimatedImageDecoder: ImageDecoding {
    public init() {}
    
    public func imageWithData(data: NSData) -> UIImage? {
        guard self.isAnimatedGIFData(data) else {
            return nil
        }
        guard let image = FLAnimatedImage(animatedGIFData: data) where image.posterImage != nil else  {
            return nil
        }
        guard let poster = image.posterImage, posterCGImage = poster.CGImage else {
            return nil
        }
        return AnimatedImage(animatedImage: image, posterImage: posterCGImage, posterImageScale: poster.scale, posterImageOrientation: poster.imageOrientation)
    }
    
    public func isAnimatedGIFData(data: NSData) -> Bool {
        let sigLength = 3
        if data.length < sigLength {
            return false
        }
        var sig = [UInt8](count: sigLength, repeatedValue: 0)
        data.getBytes(&sig, length:sigLength)
        return sig[0] == 0x47 && sig[1] == 0x49 && sig[2] == 0x46
    }
}
