// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Performs image processing.
public protocol Processing: Equatable {
    /// Returns processed image.
    func process(_ image: Image) -> Image?
}

/// Composes multiple processors.
public struct ProcessorComposition: Processing {
    private let processors: [AnyProcessor]
    
    /// Composes multiple processors.
    public init(_ processors: [AnyProcessor]) {
        self.processors = processors
    }
    
    /// Processes the given image by applying each processor in an order in
    /// which they were added. If one of the processors fails to produce
    /// an image the processing stops and `nil` is returned.
    public func process(_ input: Image) -> Image? {
        return processors.reduce(input as Image!) { image, processor in
            return autoreleasepool { image != nil ? processor.process(image!) : nil }
        }
    }
    
    /// Returns true if the underlying processors are pairwise-equivalent.
    public static func ==(lhs: ProcessorComposition, rhs: ProcessorComposition) -> Bool {
        return lhs.processors.elementsEqual(rhs.processors)
    }
}

/// Type-erased image processor.
public struct AnyProcessor: Processing {
    private let _process: (Image) -> Image?
    private let _processor: Any
    private let _equals: (AnyProcessor) -> Bool

    public init<P: Processing>(_ processor: P) {
        self._process = { processor.process($0) }
        self._processor = processor
        self._equals = { ($0._processor as? P) == processor }
    }

    public func process(_ image: Image) -> Image? {
        return self._process(image)
    }

    public static func ==(lhs: AnyProcessor, rhs: AnyProcessor) -> Bool {
        return lhs._equals(rhs)
    }
}

#if !os(macOS)

    import UIKit

    /// Decompresses and (optionally) scales down input images. Maintains
    /// original aspect ratio.
    ///
    /// Decompressing compressed image formats (such as JPEG) can significantly
    /// improve drawing performance as it allows a bitmap representation to be
    /// created in the background rather than on the main thread.
    public struct Decompressor: Processing {
        
        /// An option for how to resize the image.
        public enum ContentMode {
            /// Scales the image so that it completely fills the target size.
            /// Doesn't clip images.
            case aspectFill
            
            /// Scales the image so that it fits the target size.
            case aspectFit
        }
        
        /// Size to pass to disable resizing.
        public static let MaximumSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        private let targetSize: CGSize
        private let contentMode: ContentMode

        /// Initializes `Decompressor` with the given parameters.
        /// - parameter targetSize: Size in pixels. `MaximumSize` by default.
        /// - parameter contentMode: An option for how to resize the image
        /// to the target size. `.aspectFill` by default.
        public init(targetSize: CGSize = MaximumSize, contentMode: ContentMode = .aspectFill) {
            self.targetSize = targetSize
            self.contentMode = contentMode
        }
        
        /// Decompresses and scales the image.
        public func process(_ image: Image) -> Image? {
            return decompress(image, targetSize: targetSize, contentMode: contentMode)
        }
        
        /// Returns true if both have the same `targetSize` and `contentMode`.
        public static func ==(lhs: Decompressor, rhs: Decompressor) -> Bool {
            return lhs.targetSize == rhs.targetSize && lhs.contentMode == rhs.contentMode
        }

        #if !os(watchOS)
        /// Returns target size in pixels for the given view. Takes main screen
        /// scale into the account.
        public static func targetSize(for view: UIView) -> CGSize { // in pixels
            let scale = UIScreen.main.scale
            let size = view.bounds.size
            return CGSize(width: size.width * scale, height: size.height * scale)
        }
        #endif
    }
    
    private func decompress(_ image: UIImage, targetSize: CGSize, contentMode: Decompressor.ContentMode) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let bitmapSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scaleHor = targetSize.width / bitmapSize.width
        let scaleVert = targetSize.height / bitmapSize.height
        let scale = contentMode == .aspectFill ? max(scaleHor, scaleVert) : min(scaleHor, scaleVert)
        return decompress(image, scale: CGFloat(min(scale, 1)))
    }
    
    private func decompress(_ image: UIImage, scale: CGFloat) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let size = CGSize(width: round(scale * CGFloat(cgImage.width)), height: round(scale * CGFloat(cgImage.height)))
        
        // For more info see:
        // - Quartz 2D Programming Guide
        // - https://github.com/kean/Nuke/issues/35
        // - https://github.com/kean/Nuke/issues/57
        let alphaInfo: CGImageAlphaInfo = isOpaque(cgImage) ? .noneSkipLast : .premultipliedLast
        
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: alphaInfo.rawValue) else {
            return image
        }
        ctx.draw(cgImage, in: CGRect(origin: CGPoint.zero, size: size))
        guard let decompressed = ctx.makeImage() else { return image }
        return UIImage(cgImage: decompressed, scale: image.scale, orientation: image.imageOrientation)
    }
    
    private func isOpaque(_ image: CGImage) -> Bool {
        let alpha = image.alphaInfo
        return alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast
    }
#endif
