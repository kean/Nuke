// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
#if !os(OSX)
    import UIKit
#endif

// MARK: - Processing

/// Performs image processing.
public protocol Processing: Equatable {
    /// Returns processed image.
    func process(_ image: Image) -> Image?
}

// A type-erased image processor.
public struct AnyProcessor: Processing {
    private let _process: (Image) -> Image?
    private let _processor: Any
    private let _equator: (to: AnyProcessor) -> Bool
    
    public init<P: Processing>(_ processor: P) {
        self._process = { image in
            return processor.process(image)
        }
        self._processor = processor
        self._equator = { other in
            return (other._processor as? P) == processor
        }
    }
    
    public func process(_ image: Image) -> Image? {
        return self._process(image)
    }
    
    /// Returns true if both decompressors have the same `targetSize` and `contentMode`.
    public static func ==(lhs: AnyProcessor, rhs: AnyProcessor) -> Bool {
        return lhs._equator(to: rhs)
    }
}

// MARK: - ProcessorComposition

/// Composes multiple image processors.
public struct ProcessorComposition: Processing {
    /// Image processors that the receiver was initialized with.
    public let processors: [AnyProcessor]
    
    /// Composes multiple image processors.
    public init(processors: [AnyProcessor]) {
        self.processors = processors
    }
    
    /// Processes the given image by applying each processor in an order in which they are present in the processors array. If one of the processors fails to produce an image the processing stops and nil is returned.
    public func process(_ input: Image) -> Image? {
        return processors.reduce(input as Image!) { image, processor in
            return image != nil ? processor.process(image!) : nil
        }
    }
    
    /// Returns true if both compositions have the same number of processors, and the processors are pairwise-equivalent.
    public static func ==(lhs: ProcessorComposition, rhs: ProcessorComposition) -> Bool {
        return lhs.processors.count == rhs.processors.count &&
            !(zip(lhs.processors, rhs.processors).contains{ $0 != $1 })
    }
}

#if !os(OSX)
    
    // MARK: - ImageDecompressor
    
    /**
     Decompresses and scales input images.
     
     If the image size is bigger then the given target size (in pixels) it is resized to either fit or fill target size (see ContentMode enum for more info). Image is scaled maintaining aspect ratio.
     
     Decompression and scaling are performed in a single pass which improves performance and reduces memory usage.
     */
    public struct ImageDecompressor: Processing {
        /// An option for how to resize the image to the target size.
        public enum ContentMode {
            /// Scales the image so that it completely fills the target size. Maintains image aspect ratio. Images are not clipped.
            case aspectFill
            
            /// Scales the image so that its larger dimension fits the target size. Maintains image aspect ratio.
            case aspectFit
        }
        
        /// Size to pass when requesting the original image available for a request (image won't be resized).
        public static let MaximumSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        /// Target size in pixels. Default value is MaximumSize.
        private let targetSize: CGSize
        
        /// An option for how to resize the image to the target size. Default value is .AspectFill. See ContentMode enum for more info.
        private let contentMode: ContentMode
        
        /**
         Initializes the receiver with target size and content mode.
         
         - parameter targetSize: Target size in pixels. Default value is MaximumSize.
         - parameter contentMode: An option for how to resize the image to the target size. Default value is .AspectFill. See ContentMode enum for more info.
         */
        public init(targetSize: CGSize = MaximumSize, contentMode: ContentMode = .aspectFill) {
            self.targetSize = targetSize
            self.contentMode = contentMode
        }
        
        /// Decompresses the input image.
        public func process(_ image: Image) -> Image? {
            return decompress(image, targetSize: targetSize, contentMode: contentMode)
        }
        
        /// Returns true if both decompressors have the same `targetSize` and `contentMode`.
        public static func ==(lhs: ImageDecompressor, rhs: ImageDecompressor) -> Bool {
            return lhs.targetSize == rhs.targetSize && lhs.contentMode == rhs.contentMode
        }
    }
    
    private func decompress(_ image: UIImage, targetSize: CGSize, contentMode: ImageDecompressor.ContentMode) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let bitmapSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scaleHor = targetSize.width / bitmapSize.width
        let scaleVert = targetSize.height / bitmapSize.height
        let scale = contentMode == .aspectFill ? max(scaleHor, scaleVert) : min(scaleHor, scaleVert)
        return decompress(image, scale: CGFloat(min(scale, 1)))
    }
    
    private func decompress(_ image: UIImage, scale: CGFloat) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let size = CGSize(width: round(scale * CGFloat(cgImage.width)),
                          height: round(scale * CGFloat(cgImage.height)))
        
        // For more info see:
        // - Quartz 2D Programming Guide
        // - https://github.com/kean/Nuke/issues/35
        // - https://github.com/kean/Nuke/issues/57
        let alphaInfo: CGImageAlphaInfo = isOpaque(cgImage) ? .noneSkipLast : .premultipliedLast
        
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: alphaInfo.rawValue) else {
            return image
        }
        ctx.draw(in: CGRect(origin: CGPoint.zero, size: size), image: cgImage)
        guard let decompressed = ctx.makeImage() else { return image }
        return UIImage(cgImage: decompressed, scale: image.scale, orientation: image.imageOrientation)
    }
    
    private func isOpaque(_ image: CGImage) -> Bool {
        let alpha = image.alphaInfo
        return alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast
    }
#endif
