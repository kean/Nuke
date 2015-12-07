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

/** Creates images from image data.
*/
public protocol ImageDecoding {
    func imageWithData(data: NSData) -> Image?
}

/** Creates an image from a given data. Image scale is set to the scale of the main screen.
 */
public class ImageDecoder: ImageDecoding {
    public init() {}
    public func imageWithData(data: NSData) -> Image? {
        #if os(OSX)
            return NSImage(data: data)
        #else
            return UIImage(data: data, scale: self.imageScale)
        #endif
    }

    #if !os(OSX)
    public var imageScale: CGFloat {
        #if os(iOS) || os(tvOS)
            return UIScreen.mainScreen().scale
        #else
            return WKInterfaceDevice.currentDevice().screenScale
        #endif
    }
    #endif
}

/** Composes multiple image decoders.

 Decoders are applied in an order in which they are present in the decoders array. The decoding stops when one of the decoders produces an image.
 */
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
