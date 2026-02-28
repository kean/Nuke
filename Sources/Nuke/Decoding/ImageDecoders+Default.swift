// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

#if !os(macOS)
import UIKit
#else
import Cocoa
#endif

import ImageIO

/// A namespace with all available decoders.
public enum ImageDecoders {}

extension ImageDecoders {

    /// A decoder that supports all of the formats natively supported by the system.
    ///
    /// - note: The decoder automatically sets the scale of the decoded images to
    /// match the scale of the screen.
    ///
    /// - note: The default decoder supports progressive JPEG. It produces a new
    /// preview every time it encounters a new full frame.
    public final class Default: ImageDecoding, @unchecked Sendable {
        private(set) var numberOfScans = 0
        private var incrementalSource: CGImageSource?

        private var isPreviewForGIFGenerated = false
        private var scale: CGFloat = 1.0
        private var thumbnail: ImageRequest.ThumbnailOptions?
        private let lock = NSLock()

        public var isAsynchronous: Bool { thumbnail != nil }

        public init() { }

        public init?(context: ImageDecodingContext) {
            self.scale = context.request.scale.map { CGFloat($0) } ?? self.scale
            self.thumbnail = context.request.thumbnail
        }

        public func decode(_ data: Data) throws -> ImageContainer {
            lock.lock()
            defer { lock.unlock() }

            func makeImage() -> PlatformImage? {
                if let thumbnail {
                    return makeThumbnail(data: data,
                                         options: thumbnail,
                                         scale: scale)
                }
                return ImageDecoders.Default._decode(data, scale: scale)
            }
            guard let image = makeImage() else {
                throw ImageDecodingError.unknown
            }
            let type = AssetType(data)
            var container = ImageContainer(image: image)
            container.type = type
            if type == .gif {
                container.data = data
            }
            if numberOfScans > 0 {
                container.userInfo[.scanNumberKey] = numberOfScans
            }
            if thumbnail != nil {
                container.userInfo[.isThumbnailKey] = true
            }
            return container
        }

        public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
            lock.lock()
            defer { lock.unlock() }

            let assetType = AssetType(data)
            if assetType == .gif { // Special handling for GIF
                if !isPreviewForGIFGenerated, let image = ImageDecoders.Default._decode(data, scale: scale) {
                    isPreviewForGIFGenerated = true
                    return ImageContainer(image: image, type: .gif, isPreview: true, userInfo: [:])
                }
                return nil
            }

            if incrementalSource == nil {
                incrementalSource = CGImageSourceCreateIncremental(nil)
            }

            let source = incrementalSource!
            CGImageSourceUpdateData(source, data as CFData, false)

            let status = CGImageSourceGetStatusAtIndex(source, 0)
            guard status == .statusIncomplete || status == .statusComplete else {
                return nil
            }

            guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }

            numberOfScans += 1

            let image = ImageDecoders.Default._make(cgImage, scale: scale)
            return ImageContainer(image: image, type: assetType, isPreview: true, userInfo: [.scanNumberKey: numberOfScans])
        }
    }
}

extension ImageDecoders.Default {
    private static func _decode(_ data: Data, scale: CGFloat) -> PlatformImage? {
#if os(macOS)
        return NSImage(data: data)
#else
        return UIImage(data: data, scale: scale)
#endif
    }

    private static func _make(_ cgImage: CGImage, scale: CGFloat) -> PlatformImage {
#if os(macOS)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
#else
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
#endif
    }
}
