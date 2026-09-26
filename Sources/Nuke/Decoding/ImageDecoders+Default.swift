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
    /// - note: The decoder produces previews for the partially downloaded data
    /// according to the ``ImagePipeline/PreviewPolicy`` it is created with:
    /// either by decoding the data incrementally with Image I/O – which is how
    /// progressive JPEGs are displayed as they download – or by extracting the
    /// embedded thumbnail once. The previews are numbered in the order they are
    /// produced and the index is available in
    /// ``ImageContainer/UserInfoKey/scanNumberKey``. It is not the index of a
    /// scan in the image data: Image I/O doesn't report the scan boundaries, so
    /// with ``ImagePipeline/PreviewPolicy/incremental`` the decoder generates a
    /// preview per downloaded chunk that it manages to decode. The previews are
    /// displayed with the same orientation as the final image, and for a
    /// request with ``ImageRequest/thumbnail`` they are thumbnails as well.
    public final class Default: ImageDecoding, Sendable {
        // The decoding state is mutable and guarded by `lock`.
        /// The number of previews produced so far, including the ones generated
        /// by the ``ImagePipeline/PreviewPolicy/thumbnail`` policy and by the
        /// thumbnail fallback. Not a count of the scans in the image data.
        private(set) nonisolated(unsafe) var numberOfScans = 0
        private nonisolated(unsafe) var incrementalSource: CGImageSource?

        private nonisolated(unsafe) var didAttemptThumbnailFallback = false
        private let scale: CGFloat
        private let thumbnail: ImageRequest.ThumbnailOptions?
        let previewPolicy: ImagePipeline.PreviewPolicy
        let isAnimatedImageParsingEnabled: Bool
        private let lock = NSLock()

        /// Returns `true` when thumbnail decoding is requested, because
        /// thumbnail generation requires reading image dimensions from disk and
        /// must run on the decoding queue rather than blocking the pipeline queue.
        public var isAsynchronous: Bool { thumbnail != nil }

        /// Initializes the decoder with default settings.
        public init() {
            self.scale = 1.0
            self.thumbnail = nil
            self.previewPolicy = .incremental
            self.isAnimatedImageParsingEnabled = true
        }

        /// Initializes the decoder from the given decoding context, reading the
        /// request's scale, thumbnail options, and preview policy.
        public init?(context: ImageDecodingContext) {
            self.scale = context.request.scale
            self.thumbnail = context.request.thumbnail
            self.previewPolicy = context.previewPolicy
            self.isAnimatedImageParsingEnabled = context.isAnimatedImageParsingEnabled
        }

        public func decode(_ data: Data) throws -> ImageContainer {
            lock.lock()
            defer { lock.unlock() }

            func makeImage() -> PlatformImage? {
                if let thumbnail {
                    return makeThumbnail(data: data, options: thumbnail, scale: scale)
                }
                return ImageDecoders.Default._decode(data, scale: scale)
            }
            guard let image = makeImage() else {
                throw ImageDecodingError.unknown
            }
            let type = AssetType(data)
            var container = ImageContainer(image: image)
            container.type = type
            // Image I/O decodes only the first frame of an animation, so the
            // data travels with the image for a renderer to play it. Not for a
            // thumbnail request, where playing the full-size animation would
            // undo the downscaling.
            if thumbnail == nil, AssetType.isAnimated(data, type: type) {
                container.data = data
                // The sniff reads a header; this walks the delay of every frame,
                // so it runs here – once per image, off the main thread –
                // rather than in every view that displays it.
                if isAnimatedImageParsingEnabled {
                    container.animation = AnimatedImageSource(data: data)
                }
            }
            if numberOfScans > 0 {
                container.userInfo[.scanNumberKey] = numberOfScans
            }
            return container
        }

        public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
            lock.lock()
            defer { lock.unlock() }

            guard previewPolicy != .disabled else {
                return nil
            }

            let assetType = AssetType(data)

            // GIFs can't be decoded incrementally: Image I/O needs the complete
            // frame data, so a single preview is generated from whatever has
            // been downloaded so far regardless of the policy.
            if assetType == .gif {
                if numberOfScans == 0, let image = ImageDecoders.Default._decode(data, scale: scale) {
                    numberOfScans += 1
                    return ImageContainer(image: image, type: .gif, isPreview: true, userInfo: [.scanNumberKey: numberOfScans])
                }
                return nil
            }

            switch previewPolicy {
            case .disabled:
                return nil // Already handled above

            case .thumbnail:
                if numberOfScans > 0 { return nil } // Already generated
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: false,
                          kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
                          kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary) else {
                    return nil
                }
                numberOfScans += 1
                let image = ImageDecoders.Default._make(thumb, scale: scale)
                return ImageContainer(image: image, type: assetType, isPreview: true, userInfo: [.scanNumberKey: numberOfScans])

            case .incremental:
                if incrementalSource == nil {
                    incrementalSource = CGImageSourceCreateIncremental(nil)
                }

                let source = incrementalSource!
                CGImageSourceUpdateData(source, data as CFData, false)

                // Check that Image I/O has parsed the image dimensions before
                // attempting to create a (potentially expensive) CGImage.
                guard let orientation = _orientation(ifDimensionsAreKnownIn: source) else {
                    // Fallback: for JPEGs with large EXIF headers, the
                    // incremental source may never produce dimensions. Try
                    // generating a thumbnail from a non-incremental source once.
                    return _thumbnailFallback(data: data, assetType: assetType)
                }

                let image: PlatformImage
                if let thumbnail {
                    // A thumbnail request asks for a small image to save memory;
                    // a preview decoded at the full size of the image would undo
                    // that, so its previews are thumbnails too.
                    guard let thumb = makeThumbnail(source: source, options: thumbnail, scale: scale) else {
                        return nil
                    }
                    image = thumb
                } else {
                    guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                        return nil
                    }
                    image = ImageDecoders.Default._make(cgImage, scale: scale, orientation: orientation)
                }

                numberOfScans += 1

                return ImageContainer(image: image, type: assetType, isPreview: true, userInfo: [.scanNumberKey: numberOfScans])
            }
        }
    }
}

extension ImageDecoders.Default {
    /// Attempts to generate a thumbnail from a non-incremental source when
    /// `CGImageSourceCreateIncremental` can't parse the image (e.g. JPEGs
    /// with large EXIF headers). Only tried once per decoder instance.
    private func _thumbnailFallback(data: Data, assetType: AssetType?) -> ImageContainer? {
        guard !didAttemptThumbnailFallback else { return nil }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        // A thumbnail request caps the preview at the size it asked for.
        var maxPixelSize: CGFloat = 160
        if let thumbnail {
            maxPixelSize = min(maxPixelSize, getMaxPixelSize(for: source, options: thumbnail))
        }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary) else {
            return nil
        }
        didAttemptThumbnailFallback = true
        numberOfScans += 1
        let image = ImageDecoders.Default._make(cgImage, scale: scale)
        return ImageContainer(image: image, type: assetType, isPreview: true, userInfo: [.scanNumberKey: numberOfScans])
    }

    /// Returns the orientation the first image in the source declares once
    /// Image I/O has parsed non-zero pixel dimensions for it, and `nil` until
    /// then. Checking this before calling `CGImageSourceCreateImageAtIndex`
    /// avoids an expensive no-op when the source doesn't have enough data yet.
    private func _orientation(ifDimensionsAreKnownIn source: CGImageSource) -> CGImagePropertyOrientation? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0 && height > 0 else {
            return nil
        }
        return (properties[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init) ?? .up
    }

    private static func _decode(_ data: Data, scale: CGFloat) -> PlatformImage? {
#if os(macOS)
        return NSImage(data: data)
#else
        return UIImage(data: data, scale: scale)
#endif
    }

    /// Wraps a `CGImage` the way `_decode` displays the final image: with the
    /// EXIF orientation applied, so a preview doesn't snap a quarter turn when
    /// the download completes. Pass `.up` for an image Image I/O already
    /// transformed (`kCGImageSourceCreateThumbnailWithTransform`).
    private static func _make(_ cgImage: CGImage, scale: CGFloat, orientation: CGImagePropertyOrientation = .up) -> PlatformImage {
#if os(macOS)
        // `NSImage` can't carry an orientation, so for the rare rotated image
        // it is baked into the pixels – what `NSImage(data:)` does as well.
        let cgImage = orientation == .up ? cgImage : (cgImage.drawn(inCanvasWithSize: cgImage.size, orientation: orientation) ?? cgImage)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
#else
        return UIImage(cgImage: cgImage, scale: scale, orientation: UIImage.Orientation(orientation))
#endif
    }
}
