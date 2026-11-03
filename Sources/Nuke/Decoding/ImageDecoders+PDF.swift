// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Not on tvOS: on tvOS 27, Core Graphics crashes on a document it can't open
// instead of returning `nil`, so a damaged file would take the app down. tvOS
// 26.5 and the other platforms return `nil`.
#if !os(tvOS)

#if !os(macOS)
import UIKit
#else
import Cocoa
#endif

extension ImageDecoders {
    /// A decoder that rasterizes a page of a PDF document with Core Graphics.
    ///
    /// The decoder only runs if you register it, because every URL the app
    /// loads images from could then reach a PDF parser:
    ///
    /// ```swift
    /// ImageDecoderRegistry.shared.register(ImageDecoders.PDF.init)
    /// ```
    ///
    /// A page is measured in points and has no pixels of its own, so the decoder
    /// picks the size of the image in this order:
    ///
    /// - With ``ImageRequest/thumbnail``, the size the options ask for, even if
    ///   that is larger than the page. The page is drawn once, at that size.
    /// - Otherwise, the size of the page multiplied by ``ImageRequest/scale``.
    ///   A request with the default scale of `1` gets one pixel per point, which
    ///   looks soft on a Retina display.
    /// - Either way, the longest side stops at ``maxPixelSize``.
    ///
    /// The decoder draws no background: whatever the page doesn't paint stays
    /// transparent, and a typical page of black text needs a white view behind
    /// it. It honors the rotation and the crop box of the page.
    ///
    /// A document that can't be read, one that needs a password, and a page that
    /// doesn't exist all fail with ``ImageDecodingError/unknown``. The decoder
    /// doesn't produce previews from partially downloaded data.
    ///
    /// - note: The decoder isn't available on tvOS.
    public struct PDF: ImageDecoding, Sendable {
        /// The zero-based index of the page to draw. `0` by default.
        ///
        /// - important: The index isn't a part of the cache key. If an app shows
        /// several pages of one document, give the request for each of them its
        /// own ``ImageRequest/imageID``.
        public var pageIndex = 0

        /// The longest side of the image, in pixels. `4096` by default, which
        /// keeps an image to 64 MB at most.
        ///
        /// The media box of a page can be 14,400 points wide or more, and the
        /// size of the bitmap is the only thing that bounds what a document
        /// costs to display. The limit applies to thumbnails too.
        public var maxPixelSize: CGFloat = 4096

        private var scale: CGFloat = 1
        private var thumbnail: ImageRequest.ThumbnailOptions?

        /// Initializes the decoder with default settings.
        public init() {}

        /// Initializes the decoder from the given decoding context, reading the
        /// request's scale and thumbnail options. Returns `nil` if the data
        /// isn't a PDF document.
        public init?(context: ImageDecodingContext) {
            // Not gated on `isCompleted`: the decoder made for the first chunk
            // is the one that decodes the last, so returning `nil` here would
            // hand the whole download to the next decoder in the registry.
            guard AssetType(context.data) == .pdf else {
                return nil
            }
            self.scale = context.request.scale
            self.thumbnail = context.request.thumbnail
        }

        public func decode(_ data: Data) throws -> ImageContainer {
            guard let provider = CGDataProvider(data: data as CFData),
                  let document = CGPDFDocument(provider),
                  document.isUnlocked, // Quartz tries the empty password on its own
                  pageIndex >= 0, pageIndex < document.numberOfPages,
                  let page = document.page(at: pageIndex + 1), // Numbered from one
                  let cgImage = draw(page) else {
                throw ImageDecodingError.unknown
            }
            // `data` stays empty, as it does for any image that isn't animated:
            // the disk cache gets the document from the pipeline, and nothing
            // reads it from the container.
            return ImageContainer(image: makeImage(from: cgImage), type: .pdf)
        }

        private func draw(_ page: CGPDFPage) -> CGImage? {
            let box = page.getBoxRect(.cropBox)
            // `/Rotate` turns the page, so a quarter turn swaps its sides.
            let isSideways = page.rotationAngle % 180 != 0
            let pageSize = isSideways ? CGSize(width: box.height, height: box.width) : box.size
            guard pageSize.isFinite, pageSize.width > 0, pageSize.height > 0 else {
                return nil
            }
            let size = pixelSize(forPageSize: pageSize)
            guard let width = size.width.pixelDimension,
                  let height = size.height.pixelDimension,
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return nil
            }
            context.interpolationQuality = .high
            // The drawing transform handles the rotation and the origin of the
            // crop box, but it never scales up, which would leave a small page
            // in the middle of a large bitmap. So it maps the page onto a rect
            // of its own size, and the context does the scaling.
            context.scaleBy(x: CGFloat(width) / pageSize.width, y: CGFloat(height) / pageSize.height)
            let rect = CGRect(origin: .zero, size: pageSize)
            context.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            return context.makeImage()
        }

        private func pixelSize(forPageSize size: CGSize) -> CGSize {
            let longestSide = max(size.width, size.height)
            let requested: CGFloat
            if let thumbnail {
                if thumbnail.options.contains(.flexible) {
                    requested = size.getScale(targetSize: thumbnail.size.cgSize, contentMode: thumbnail.contentMode)
                } else {
                    requested = CGFloat(thumbnail.size.width) / longestSide
                }
            } else {
                requested = scale
            }
            let pixelsPerPoint = min(requested, maxPixelSize / longestSide)
            return CGSize(
                width: max(1, (size.width * pixelsPerPoint).rounded()),
                height: max(1, (size.height * pixelsPerPoint).rounded())
            )
        }

        private func makeImage(from cgImage: CGImage) -> PlatformImage {
#if os(macOS)
            NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale))
#else
            UIImage(cgImage: cgImage, scale: scale, orientation: .up)
#endif
        }
    }
}

#endif
