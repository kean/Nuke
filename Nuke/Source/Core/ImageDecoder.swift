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

/** Decodes data into an image object.
 */
public protocol ImageDecoding {
    /* Decodes data into an image object.
     */
    func decode(data: NSData) -> Image?
}

/** Decodes data into an image object. Image scale is set to the scale of the main screen.
 */
public class ImageDecoder: ImageDecoding {
    /** Initializes the receiver.
     */
    public init() {}

    /** Decodes data into an image object using native methods.
    */
    public func decode(data: NSData) -> Image? {
        #if os(OSX)
            return NSImage(data: data)
        #else
            return UIImage(data: data, scale: self.imageScale)
        #endif
    }

    #if !os(OSX)
    /** Returns the scale of the main screen.
     */
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
 */
public class ImageDecoderComposition: ImageDecoding {
    /** Image decoders that the receiver was initialized with.
     */
    public let decoders: [ImageDecoding]

    /** Composes multiple image decoders.
     */
    public init(decoders: [ImageDecoding]) {
        self.decoders = decoders
    }

    /** Decoders are applied in an order in which they are present in the decoders array. The decoding stops when one of the decoders produces an image.
     */
    public func decode(data: NSData) -> Image? {
        for decoder in self.decoders {
            if let image = decoder.decode(data) {
                return image
            }
        }
        return nil
    }
}
