// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

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
        private var scale: CGFloat = 1.0
        private var thumbnail: ImageRequest.ThumbnailOptions?
        private let lock = NSLock()

        public var isAsynchronous: Bool { thumbnail != nil }

        public init() { }

        /// Returns `nil` if progressive decoding is not allowed for the given
        /// content.
        public init?(context: ImageDecodingContext) {
            self.scale = context.request.scale.map { CGFloat($0) } ?? self.scale
            self.thumbnail = context.request.thumbnail

            if !context.isCompleted && !isProgressiveDecodingAllowed(for: context.data) {
                return nil // Progressive decoding not allowed for this image
            }
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

            guard let endOfScan = scanner.scan(data), endOfScan > 0 else {
                return nil
            }
            
            // To decode data correctly, binary needs to end with an EOI (End Of Image) marker (0xFFD9)
            var imageData = data[0...endOfScan]
            if data[endOfScan - 1] != 0xFF || data[endOfScan] != 0xD9 {
                imageData += [0xFF, 0xD9]
            }
            // We could be appending the data to `CGImageSourceCreateIncremental` and producing `CGImage`s from there but the EOI addition forces us to have to finalize everytime, which counters any performance gains.
            guard let image = ImageDecoders.Default._decode(imageData, scale: scale) else {
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
        if scannedIndex < 0 {
            guard let header = ImageProperties.JPEG(data),
                  header.isProgressive else {
                return nil
            }
            
            // we always want to start after the Start-Of-Frame marker to skip over any thumbnail markers which could interfere with the parsing
            scannedIndex = header.startOfFrameOffset + 2
        }
        
        // Check if there is more data to scan.
        guard (scannedIndex + 1) < data.count else {
            return nil
        }

        // Start scanning from the where it left off previous time.
        // 1. we use `Data.firstIndex` as it's faster than iterating byte-by-byte in Swift
        // 2. we could use `.lastIndex` and be much faster but we want to keep track of scan number
        var numberOfScans = self.numberOfScans
        var searchRange = (scannedIndex + 1)..<data.count
        // 0xFF, 0xDA - Start Of Scan
        while let nextMarker = data[searchRange].firstIndex(of: 0xFF),
              nextMarker < data.count - 1  {
            if data[nextMarker + 1] == 0xDA {
                numberOfScans += 1
                lastStartOfScan = nextMarker
                scannedIndex = nextMarker + 1
            } else {
                scannedIndex = nextMarker
            }
            searchRange = (scannedIndex + 1)..<data.count
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
    private static func _decode(_ data: Data, scale: CGFloat) -> PlatformImage? {
#if os(macOS)
        return NSImage(data: data)
#else
        return UIImage(data: data, scale: scale)
#endif
    }
}

enum ImageProperties {}


// Keeping this private for now, not sure neither about the API, not the implementation.
extension ImageProperties {
    struct JPEG {
        var isProgressive: Bool
        var startOfFrameOffset: Int

        init?(_ data: Data) {
            guard let header = Self.parseHeader(data) else {
                return nil
            }
            self = header
        }
        
        private init (isProgressive: Bool, startOfFrameOffset: Int) {
            self.isProgressive = isProgressive
            self.startOfFrameOffset = startOfFrameOffset
        }
        
        // This is the most accurate way to determine whether this is a progressive JPEG, but sometimes can come back nil for baseline JPEGs
        private static func isProgressive_io(_ data: Data) -> Bool? {
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(imageSource) > 0 else {
                return nil
            }
            
            // Get the properties for the first image
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
            let jfifProperties = properties?[kCGImagePropertyJFIFDictionary] as? [CFString: Any]
            
            // this property might be missing for baseline JPEGs so we can't depend on this completely
            if let isProgressive = jfifProperties?[kCGImagePropertyJFIFIsProgressive] as? Bool {
                return isProgressive
            }
            
            return nil
        }
        
        // Manually walk through JPEG header
        static func parseHeader(_ data: Data) -> JPEG? {
            // JPEG starts with SOI marker (FF D8)
            guard data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 else {
                return nil
            }
            
            // Start after SOI marker
            var searchRange = 2..<data.count
            
            // Process all segments until we find an SOF marker or reach the end
            while let nextMarker = data[searchRange].firstIndex(of: 0xFF),
                  nextMarker < data.count - 1 {
                
                // Skip Padding
                var controlIndex = nextMarker + 1
                while data[controlIndex] == 0xFF {
                    controlIndex += 1
                    if controlIndex >= data.count {
                        break
                    }
                }
                
                // The byte coming after 0xFF gives us the information
                let marker = data[controlIndex]
                
                // Check for SOF markers that indicate encoding type
                // 0xFF, 0xC0 - Start Of Frame (baseline DCT)
                // 0xFF, 0xC2 - Start Of Frame (progressive DCT)
                // https://en.wikipedia.org/wiki/JPEG
                // WARNING: These markers may also appear as part of a thumbnail in exif segment, so we need to make sure we skip these segments
                let offset = controlIndex - 1
                if marker == 0xC0 {
                    return JPEG(isProgressive: false, startOfFrameOffset: offset)
                } else if marker == 0xC2 {
                    return JPEG(isProgressive: true, startOfFrameOffset: offset)
                }
                
                // Next iteration we look for the next 0xFF byte after this one
                searchRange = (controlIndex + 1)..<data.count
                
                // Handle markers without length fields (like RST markers, TEM, etc.)
                if (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01 {
                    // These markers have no data segment
                    continue
                }
                
                // Handle EOI (End of Image)
                guard marker != 0xD9 else {
                    break
                }
                
                // Handle SOS (Start of Scan) - if we've reached this place we've missed the SOF marker
                guard marker != 0xDA else {
                    break
                }
                
                // All other markers have a length field, make sure we have enough bytes for the length
                let lengthIndex = controlIndex + 1
                guard lengthIndex < data.count - 1 else {
                    break
                }
                
                // Read the length (includes the length bytes themselves)
                let length = UInt16(data[lengthIndex]) << 8 | UInt16(data[lengthIndex + 1])
                
                // Skip this segment (length includes the 2 length bytes, so should be at least 2)
                guard length > 2 else {
                    // Invalid length, corrupted JPEG
                    break
                }
                
                let frontier = lengthIndex + Int(length)
                guard frontier < data.count else {
                    // we don't have enough data to reach end of this segment
                    break
                }
                
                searchRange = frontier..<data.count
            }
            
            // If we reached this part we haven't found SOF marker, likely data is not complete
            return nil
        }
    }
}
