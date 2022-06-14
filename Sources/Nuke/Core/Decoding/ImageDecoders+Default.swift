// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

#if !os(macOS)
import UIKit
#else
import Cocoa
#endif

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
        // Number of scans that the decoder has found so far. The last scan might be
        // incomplete at this point.
        var numberOfScans: Int { scanner.numberOfScans }
        private var scanner = ProgressiveJPEGScanner()

        private var isPreviewForGIFGenerated = false
        private var scale: CGFloat?
        private var thumbnail: ImageRequest.ThumbnailOptions?
        private let lock = NSLock()

        public var isAsynchronous: Bool { thumbnail != nil }

        public init() { }

        /// Returns `nil` if progressive decoding is not allowed for the given
        /// content.
        public init?(context: ImageDecodingContext) {
            self.scale = context.request.scale.map { CGFloat($0) }
            self.thumbnail = context.request.thubmnail

            if !context.isCompleted && !isProgressiveDecodingAllowed(for: context.data) {
                return nil // Progressive decoding not allowed for this image
            }
        }

        public func decode(_ data: Data) throws -> ImageContainer {
            lock.lock()
            defer { lock.unlock() }

            func makeImage() -> PlatformImage? {
                if let thumbnail = self.thumbnail {
                    return makeThumbnail(data: data, options: thumbnail)
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

            guard let endOfScan = scanner.scan(data), endOfScan > 0 else {
                return nil
            }
            guard let image = ImageDecoders.Default._decode(data[0...endOfScan], scale: scale) else {
                return nil
            }
            return ImageContainer(image: image, type: assetType, isPreview: true, userInfo: [.scanNumberKey: numberOfScans])
        }
    }
}

private func isProgressiveDecodingAllowed(for data: Data) -> Bool {
   let assetType = AssetType(data)

   // Determined whether the image supports progressive decoding or not
   // (only proressive JPEG is allowed for now, but you can add support
   // for other formats by implementing your own decoder).
   if assetType == .jpeg, ImageProperties.JPEG(data)?.isProgressive == true {
       return true
   }

   // Generate one preview for GIF.
   if assetType == .gif {
       return true
   }

   return false
}

private struct ProgressiveJPEGScanner: Sendable {
    // Number of scans that the decoder has found so far. The last scan might be
    // incomplete at this point.
    private(set) var numberOfScans = 0
    private var lastStartOfScan: Int = 0 // Index of the last found Start of Scan
    private var scannedIndex: Int = -1 // Index at which previous scan was finished

    /// Scans the given data. If finds new scans, returns the last index of the
    /// last available scan.
    mutating func scan(_ data: Data) -> Int? {
        // Check if there is more data to scan.
        guard (scannedIndex + 1) < data.count else {
            return nil
        }

        // Start scanning from the where it left off previous time.
        var index = (scannedIndex + 1)
        var numberOfScans = self.numberOfScans
        while index < (data.count - 1) {
            scannedIndex = index
            // 0xFF, 0xDA - Start Of Scan
            if data[index] == 0xFF, data[index + 1] == 0xDA {
                lastStartOfScan = index
                numberOfScans += 1
            }
            index += 1
        }

        // Found more scans this the previous time
        guard numberOfScans > self.numberOfScans else {
            return nil
        }
        self.numberOfScans = numberOfScans

        // `> 1` checks that we've received a first scan (SOS) and then received
        // and also received a second scan (SOS). This way we know that we have
        // at least one full scan available.
        guard numberOfScans > 1 && lastStartOfScan > 0 else {
            return nil
        }

        return lastStartOfScan - 1
    }
}

extension ImageDecoders.Default {
    private static func _decode(_ data: Data, scale: CGFloat?) -> PlatformImage? {
        #if os(macOS)
        return NSImage(data: data)
        #else
        return UIImage(data: data, scale: scale ?? Screen.scale)
        #endif
    }
}

enum ImageProperties {}

// Keeping this private for now, not sure neither about the API, not the implementation.
extension ImageProperties {
    struct JPEG {
        var isProgressive: Bool

        init?(_ data: Data) {
            guard let isProgressive = ImageProperties.JPEG.isProgressive(data) else {
                return nil
            }
            self.isProgressive = isProgressive
        }

        private static func isProgressive(_ data: Data) -> Bool? {
            var index = 3 // start scanning right after magic numbers
            while index < (data.count - 1) {
                // A example of first few bytes of progressive jpeg image:
                // FF D8 FF E0 00 10 4A 46 49 46 00 01 01 00 00 48 00 ...
                //
                // 0xFF, 0xC0 - Start Of Frame (baseline DCT)
                // 0xFF, 0xC2 - Start Of Frame (progressive DCT)
                // https://en.wikipedia.org/wiki/JPEG
                //
                // As an alternative, Image I/O provides facilities to parse
                // JPEG metadata via CGImageSourceCopyPropertiesAtIndex. It is a
                // bit too convoluted to use and most likely slightly less
                // efficient that checking this one special bit directly.
                if data[index] == 0xFF {
                    if data[index + 1] == 0xC2 {
                        return true
                    }
                    if data[index + 1] == 0xC0 {
                        return false // baseline
                    }
                }
                index += 1
            }
            return nil
        }
    }
}
