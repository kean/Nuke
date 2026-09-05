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
    /// preview per downloaded chunk that it manages to decode.
    public final class Default: ImageDecoding, @unchecked Sendable {
        /// The number of previews produced so far, including the ones generated
        /// by the ``ImagePipeline/PreviewPolicy/thumbnail`` policy and by the
        /// thumbnail fallback. Not a count of the scans in the image data.
        private(set) var numberOfScans = 0
        private var incrementalSource: CGImageSource?

        private var isPreviewForGIFGenerated = false
        private var didAttemptThumbnailFallback = false
        private var scale: CGFloat = 1.0
        private var thumbnail: ImageRequest.ThumbnailOptions?
        private(set) var previewPolicy: ImagePipeline.PreviewPolicy = .incremental
        private(set) var isAnimatedImageParsingEnabled = true
        private let lock = NSLock()

        /// Returns `true` when thumbnail decoding is requested, because
        /// thumbnail generation requires reading image dimensions from disk and
        /// must run on the decoding queue rather than blocking the pipeline queue.
        public var isAsynchronous: Bool { thumbnail != nil }

        /// Initializes the decoder with default settings.
        public init() { }

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
                if !isPreviewForGIFGenerated, let image = ImageDecoders.Default._decode(data, scale: scale) {
                    isPreviewForGIFGenerated = true
                    return ImageContainer(image: image, type: .gif, isPreview: true, userInfo: [:])
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
                          kCGImageSourceCreateThumbnailFromImageIfAbsent: false
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
                guard _hasImageDimensions(source) else {
                    // Fallback: for JPEGs with large EXIF headers, the
                    // incremental source may never produce dimensions. Try
                    // generating a thumbnail from a non-incremental source once.
                    return _thumbnailFallback(data: data, assetType: assetType)
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
}

extension ImageDecoders.Default {
    /// Attempts to generate a thumbnail from a non-incremental source when
    /// `CGImageSourceCreateIncremental` can't parse the image (e.g. JPEGs
    /// with large EXIF headers). Only tried once per decoder instance.
    private func _thumbnailFallback(data: Data, assetType: AssetType?) -> ImageContainer? {
        guard !didAttemptThumbnailFallback else { return nil }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                  kCGImageSourceThumbnailMaxPixelSize: 160
              ] as CFDictionary) else {
            return nil
        }
        didAttemptThumbnailFallback = true
        numberOfScans += 1
        let image = ImageDecoders.Default._make(cgImage, scale: scale)
        return ImageContainer(image: image, type: assetType, isPreview: true, userInfo: [.scanNumberKey: numberOfScans])
    }

    /// Returns `true` if Image I/O has parsed non-zero pixel dimensions for the
    /// first image in the source. Checking this before calling
    /// `CGImageSourceCreateImageAtIndex` avoids an expensive no-op when the
    /// source doesn't have enough data yet.
    private func _hasImageDimensions(_ source: CGImageSource) -> Bool {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return false
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return width > 0 && height > 0
    }

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
