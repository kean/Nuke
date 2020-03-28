// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

#if !os(macOS)
import UIKit
#else
import Cocoa
#endif

#if os(watchOS)
import WatchKit
#endif

// MARK: - ImageDecoding

/// Decodes image data.
public protocol ImageDecoding {
    /// Produces an image from the image data. A decoder is a one-shot object
    /// created for a single image decoding session. If image pipeline has
    /// progressive decoding enabled, the `decode(data:isFinal:)` method gets
    /// called each time the data buffer has new data available. The decoder may
    /// decide whether or not to produce a new image based on the previous scans.
    func decode(data: Data, isFinal: Bool) -> PlatformImage?
}

extension ImageDecoding {
    public func decode(data: Data) -> PlatformImage? {
        return self.decode(data: data, isFinal: true)
    }
}

extension ImageDecoding {
    func decode(_ data: Data, urlResponse: URLResponse?, isFinal: Bool) -> ImageResponse? {
        func decode() -> ImageContainer? {
            if let newDecoder = self as? _ImageDecoding {
                // If it is the old implementation, call the old method. Otherwise,
                  // call the new APIs.
                if isFinal {
                    return newDecoder.decode(data: data)
                } else {
                    return newDecoder.decodePartiallyDownloadedData(data)
                }
            } else {
                guard let image = self.decode(data: data, isFinal: isFinal) else {
                    return nil
                }
                return ImageContainer(image: image, data: image.animatedImageData, userInfo: [:])
            }
        }
        guard let container = autoreleasepool(invoking: decode) else {
            return nil
        }
        #if !os(macOS)
        ImageDecompression.setDecompressionNeeded(true, for: container.image)
        #endif

        return ImageResponse(container: container, urlResponse: urlResponse)
    }
}

// Soft-deprecated in Nuke 8.5.
public typealias ImageDecoder = ImageDecoders.Default

// MARK: - ImageDecoders

public enum ImageDecoders {}

// MARK: - ImageDecoders.Default

// An image decoder that uses native APIs. Supports progressive decoding.
// The decoder is stateful.
public extension ImageDecoders {

    final class Default: _ImageDecoding {
        // `nil` if decoder hasn't detected whether progressive decoding is enabled.
        private(set) var isProgressive: Bool?
        // Number of scans that the decoder has found so far. The last scan might be
        // incomplete at this point.
        private var numberOfScans = 0
        private var lastStartOfScan: Int = 0 // Index of the last found Start of Scan
        private var scannedIndex: Int = -1 // Index at which previous scan was finished

        /// A user info key to get the scan number (Int).
        public static let scanNumberKey = "ImageDecoders.Default.scanNumberKey"

        public init() { }

        public func decode(data: Data) -> ImageContainer? {
            let format = ImageFormat.format(for: data)

            guard let image = ImageDecoders.Default.decode(data) else {
                return nil
            }
            // Keep original data around in case of GIF
            if ImagePipeline.Configuration.isAnimatedImageDataEnabled, case .gif? = format {
                image.animatedImageData = data
            }
            var container = ImageContainer(image: image, data: image.animatedImageData)
            if isProgressive == true {
                container.userInfo[ImageDecoders.Default.scanNumberKey] = numberOfScans
            }
            return container
        }

        public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
            let format = ImageFormat.format(for: data)

            // Determined (if haven't determined yet) whether the image supports progressive
            // decoding or not (only proressive JPEG is allowed for now, but you can
            // add support for other formats by implementing your own decoder).
            isProgressive = isProgressive ?? format?.isProgressive
            guard isProgressive == true else {
                return nil
            }

            // Check if there is more data to scan.
            guard (scannedIndex + 1) < data.count else {
                return nil
            }

            // Start scaning from the where it left off previous time.
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
            guard let image = ImageDecoder.decode(data[0..<lastStartOfScan]) else {
                return nil
            }
            return ImageContainer(image: image, userInfo: [ImageDecoders.Default.scanNumberKey: numberOfScans])
        }
    }
}

extension ImageDecoders.Default {
    static func decode(_ data: Data) -> PlatformImage? {
        #if os(macOS)
        return NSImage(data: data)
        #else
        return UIImage(data: data, scale: Screen.scale)
        #endif
    }
}

// MARK: - ImageDecoders.Empty

public extension ImageDecoders {
    /// A decoder which returns an empty placeholder image and attaches image
    /// data to the image container.
    struct Empty: _ImageDecoding {
        public let isProgressive: Bool

        /// - parameter isProgressive: If `false`, returns nil for every progressive
        /// scan. `false` by default.
        public init(isProgressive: Bool = false) {
            self.isProgressive = isProgressive
        }

        public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
            return isProgressive ? ImageContainer(image: PlatformImage(), data: data, userInfo: [:]) : nil
        }

        public func decode(data: Data) -> ImageContainer? {
            return ImageContainer(image: PlatformImage(), data: data, userInfo: [:])
        }
    }
}

// MARK: _ImageDecoding

/// A new experimental image decoder.
///
/// A decoder is a one-shot object created for a single image decoding session.
///
/// - note: If you need additional information in the decoder, you can pass
/// anything that you might need from the `ImageDecodingContext`.
public protocol _ImageDecoding: ImageDecoding {
    /// Produces an image from the given image data.
    func decode(data: Data) -> ImageContainer?

    /// Produces an image from the given partially dowloaded image data.
    /// This method might be called multiple times during a single decoding
    /// session. When the image download is complete, `decode(data:)` method is called.
    ///
    /// - returns: nil by default.
    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer?
}

public extension _ImageDecoding {
    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        return nil
    }

    func decode(data: Data, isFinal: Bool) -> PlatformImage? {
        if isFinal {
            return self.decode(data: data)?.image
        } else {
            return self.decodePartiallyDownloadedData(data)?.image
        }
    }
}

// MARK: - ImageDecoderRegistry

/// A register of image codecs (only decoding).
public final class ImageDecoderRegistry {
    /// A shared registry.
    public static let shared = ImageDecoderRegistry()

    private var matches = [(ImageDecodingContext) -> ImageDecoding?]()

    /// Returns a decoder which matches the given context.
    public func decoder(for context: ImageDecodingContext) -> ImageDecoding {
        for match in matches {
            if let decoder = match(context) {
                return decoder
            }
        }
        return ImageDecoders.Default() // Return default decoder if couldn't find a custom one.
    }

    /// Registers a decoder to be used in a given decoding context. The closure
    /// is going to be executed before all other already registered closures.
    public func register(_ match: @escaping (ImageDecodingContext) -> ImageDecoding?) {
        matches.insert(match, at: 0)
    }

    func clear() {
        matches = []
    }
}

/// Image decoding context used when selecting which decoder to use.
public struct ImageDecodingContext {
    public let request: ImageRequest
    public let data: Data
    public let urlResponse: URLResponse?

    public init(request: ImageRequest, data: Data, urlResponse: URLResponse?) {
        self.request = request
        self.data = data
        self.urlResponse = urlResponse
    }
}

// MARK: - Image Formats

enum ImageFormat: Equatable {
    /// `isProgressive` is nil if we determined that it's a jpeg, but we don't
    /// know if it is progressive or baseline yet.
    case jpeg(isProgressive: Bool?)
    case png
    case gif

    // Returns `nil` if not enough data.
    static func format(for data: Data) -> ImageFormat? {
        // JPEG magic numbers https://en.wikipedia.org/wiki/JPEG
        if _match(data, [0xFF, 0xD8, 0xFF]) {
            var index = 3 // start scanning right after magic numbers
            while index < (data.count - 1) {
                // A example of first few bytes of progressive jpeg image:
                // FF D8 FF E0 00 10 4A 46 49 46 00 01 01 00 00 48 00 ...
                //
                // 0xFF, 0xC0 - Start Of Frame (baseline DCT)
                // 0xFF, 0xC2 - Start Of Frame (progressive DCT)
                // https://en.wikipedia.org/wiki/JPEG
                if data[index] == 0xFF {
                    if data[index + 1] == 0xC2 {
                        return .jpeg(isProgressive: true) // progressive
                    }
                    if data[index + 1] == 0xC0 {
                        return .jpeg(isProgressive: false) // baseline
                    }
                }
                index += 1
            }
            // It's a jpeg but we don't know if progressive or not yet.
            return .jpeg(isProgressive: nil)
        }

        // GIF magic numbers https://en.wikipedia.org/wiki/GIF
        if _match(data, [0x47, 0x49, 0x46]) {
            return .gif
        }

        // PNG Magic numbers https://en.wikipedia.org/wiki/Portable_Network_Graphics
        if _match(data, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return .png
        }

        // Either not enough data, or we just don't know this format yet.
        return nil
    }

    var isProgressive: Bool? {
        if case let .jpeg(isProgressive) = self {
            return isProgressive
        }
        return false
    }

    private static func _match(_ data: Data, _ numbers: [UInt8]) -> Bool {
        guard data.count >= numbers.count else {
            return false
        }
        return !zip(numbers.indices, numbers).contains { (index, number) in
            data[index] != number
        }
    }
}

// MARK: - Animated Images

private var _animatedImageDataAK = "Nuke.AnimatedImageData.AssociatedKey"

extension PlatformImage {
    // Soft-deprecated in Nuke 8.5
    // Animated image data. Only not `nil` when image data actually contains
    // an animated image.
    public var animatedImageData: Data? {
        get { return objc_getAssociatedObject(self, &_animatedImageDataAK) as? Data }
        set { objc_setAssociatedObject(self, &_animatedImageDataAK, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
