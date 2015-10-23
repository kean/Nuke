// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

#if os(watchOS)
    import WatchKit
#endif

public protocol ImageDecoding {
    func imageWithData(data: NSData) -> Image?
}

public class ImageDecoder: ImageDecoding {
    public init() {}
    public func imageWithData(data: NSData) -> Image? {
        #if os(OSX)
            return NSImage(data: data)
        #elseif os(iOS) || os(tvOS)
            return UIImage(data: data, scale: UIScreen.mainScreen().scale)
        #else
            return UIImage(data: data, scale: WKInterfaceDevice.currentDevice().screenScale)
        #endif
    }
}

public class ImageDecoderComposition: ImageDecoding {
    public let decoders: [ImageDecoding]
    
    public init(decoders: [ImageDecoding]) {
        self.decoders = decoders
    }
    
    public func imageWithData(data: NSData) -> Image? {
        for decoder in self.decoders {
            if let image = decoder.imageWithData(data) {
                return image
            }
        }
        return nil
    }
}
