// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

#if !os(macOS)
import UIKit
#else
import Cocoa
#endif

#if os(watchOS)
import WatchKit
#endif

// MARK: - ImageDecoding

/// An image decoder.
///
/// A decoder is a one-shot object created for a single image decoding session.
///
/// - note: If you need additional information in the decoder, you can pass
/// anything that you might need from the `ImageDecodingContext`.
public protocol ImageDecoding {
    /// Return `true` if you want the decoding to be performed on the decoding
    /// queue (see `imageDecodingQueue`). If `false`, the decoding will be
    /// performed synchronously on the pipeline operation queue. By default, `true`.
    var isAsynchronous: Bool { get }

    /// Produces an image from the given image data.
    func decode(_ data: Data) -> ImageContainer?

    /// Produces an image from the given partially dowloaded image data.
    /// This method might be called multiple times during a single decoding
    /// session. When the image download is complete, `decode(data:)` method is called.
    ///
    /// - returns: nil by default.
    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer?
}

extension ImageDecoding {
    /// Returns `true` by default.
    public var isAsynchronous: Bool {
        true
    }

    /// The default implementation which simply returns `nil` (no progressive
    /// decoding available).
    public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        nil
    }
}

extension ImageDecoding {
    func decode(_ data: Data, urlResponse: URLResponse?, isCompleted: Bool, cacheType: ImageResponse.CacheType?) -> ImageResponse? {
        func _decode() -> ImageContainer? {
            if isCompleted {
                return decode(data)
            } else {
                return decodePartiallyDownloadedData(data)
            }
        }
        guard let container = autoreleasepool(invoking: _decode) else {
            return nil
        }
        #if !os(macOS)
        ImageDecompression.setDecompressionNeeded(true, for: container.image)
        #endif
        return ImageResponse(container: container, urlResponse: urlResponse, cacheType: cacheType)
    }
}

// MARK: - ImageDecoders

/// A namespace with all available decoders.
public enum ImageDecoders {}

// MARK: - ImageDecoders.Default

extension ImageDecoders {

    /// A decoder that supports all of the formats natively supported by the system.
    ///
    /// - note: The decoder automatically sets the scale of the decoded images to
    /// match the scale of the screen.
    ///
    /// - note: The default decoder supports progressive JPEG. It produces a new
    /// preview every time it encounters a new full frame.
    public final class Default: ImageDecoding, ImageDecoderRegistering {
        // Number of scans that the decoder has found so far. The last scan might be
        // incomplete at this point.
        var numberOfScans: Int { scanner.numberOfScans }
        private var scanner = ProgressiveJPEGScanner()

        private var container: ImageContainer?

        private var isDecodingGIFProgressively = false
        private var isPreviewForGIFGenerated = false
        private var scale: CGFloat?

        public init() { }

        public var isAsynchronous: Bool {
            false
        }

        public init?(data: Data, context: ImageDecodingContext) {
            let scale = context.request.ref.userInfo?[.scaleKey]
            self.scale = (scale as? NSNumber).map { CGFloat($0.floatValue) }
            guard let container = _decode(data) else {
                return nil
            }
            self.container = container
        }

        public init?(partiallyDownloadedData data: Data, context: ImageDecodingContext) {
            let imageType = ImageType(data)

            self.scale = context.request.ref.userInfo?[.scaleKey] as? CGFloat

            // Determined whether the image supports progressive decoding or not
            // (only proressive JPEG is allowed for now, but you can add support
            // for other formats by implementing your own decoder).
            if imageType == .jpeg, ImageProperties.JPEG(data)?.isProgressive == true {
                return
            }

            // Generate one preview for GIF.
            if imageType == .gif {
                self.isDecodingGIFProgressively = true
                return
            }

            return nil
        }

        public func decode(_ data: Data) -> ImageContainer? {
            container ?? _decode(data)
        }

        private func _decode(_ data: Data) -> ImageContainer? {
            guard let image = ImageDecoders.Default._decode(data, scale: scale) else {
                return nil
            }
            // Keep original data around in case of GIF
            let type = ImageType(data)
            if ImagePipeline.Configuration._isAnimatedImageDataEnabled, type == .gif {
                image._animatedImageData = data
            }
            var container = ImageContainer(image: image, data: image._animatedImageData)
            container.type = type
            if type == .gif {
                container.data = data
            }
            if numberOfScans > 0 {
                container.userInfo[.scanNumberKey] = numberOfScans
            }
            return container
        }

        public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
            if isDecodingGIFProgressively { // Special handling for GIF
                if !isPreviewForGIFGenerated, let image = ImageDecoders.Default._decode(data, scale: scale) {
                    isPreviewForGIFGenerated = true
                    return ImageContainer(image: image, type: .gif, isPreview: true, data: nil, userInfo: [:])
                }
                return nil
            }

            guard let endOfScan = scanner.scan(data), endOfScan > 0 else {
                return nil
            }
            guard let image = ImageDecoders.Default._decode(data[0...endOfScan], scale: scale) else {
                return nil
            }
            return ImageContainer(image: image, type: .jpeg, isPreview: true, userInfo: [.scanNumberKey: numberOfScans])
        }
    }
}

private struct ProgressiveJPEGScanner {
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

        return lastStartOfScan - 1
    }
}

extension ImageDecoders.Default {
    static func _decode(_ data: Data, scale: CGFloat?) -> PlatformImage? {
        #if os(macOS)
        return NSImage(data: data)
        #else
        return UIImage(data: data, scale: scale ?? Screen.scale)
        #endif
    }
}

// MARK: - ImageDecoders.Empty

extension ImageDecoders {
    /// A decoder that returns an empty placeholder image and attaches image
    /// data to the image container.
    public struct Empty: ImageDecoding {
        public let isProgressive: Bool
        private let imageType: ImageType?

        public var isAsynchronous: Bool {
            false
        }

        /// Initializes the decoder.
        ///
        /// - Parameters:
        ///   - type: Image type to be associated with an image container.
        ///   `nil` by defalt.
        ///   - isProgressive: If `false`, returns nil for every progressive
        ///   scan. `false` by default.
        public init(imageType: ImageType? = nil, isProgressive: Bool = false) {
            self.imageType = imageType
            self.isProgressive = isProgressive
        }

        public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
            isProgressive ? ImageContainer(image: PlatformImage(), type: imageType, data: data, userInfo: [:]) : nil
        }

        public func decode(_ data: Data) -> ImageContainer? {
            ImageContainer(image: PlatformImage(), type: imageType, data: data, userInfo: [:])
        }
    }
}

// MARK: - ImageDecoderRegistering

/// An image decoder which supports automatically registering in the decoder register.
public protocol ImageDecoderRegistering: ImageDecoding {
    /// Returns non-nil if the decoder can be used to decode the given data.
    ///
    /// - parameter data: The same data is going to be delivered to decoder via
    /// `decode(_:)` method. The same instance of the decoder is going to be used.
    init?(data: Data, context: ImageDecodingContext)

    /// Returns non-nil if the decoder can be used to progressively decode the
    /// given partially downloaded data.
    ///
    /// - parameter data: The first and the next data chunks are going to be
    /// delivered to the decoder via `decodePartiallyDownloadedData(_:)` method.
    init?(partiallyDownloadedData data: Data, context: ImageDecodingContext)
}

public extension ImageDecoderRegistering {
    /// The default implementation which simply returns `nil` (no progressive
    /// decoding available).
    init?(partiallyDownloadedData data: Data, context: ImageDecodingContext) {
        return nil
    }
}

// MARK: - ImageDecoderRegistry

/// A registry of image codecs.
public final class ImageDecoderRegistry {
    /// A shared registry.
    public static let shared = ImageDecoderRegistry()

    private struct Match {
        let closure: (ImageDecodingContext) -> ImageDecoding?
    }

    private var matches = [Match]()

    public init() {
        self.register(ImageDecoders.Default.self)
    }

    /// Returns a decoder which matches the given context.
    public func decoder(for context: ImageDecodingContext) -> ImageDecoding? {
        for match in matches {
            if let decoder = match.closure(context) {
                return decoder
            }
        }
        return nil
    }

    // MARK: - Registering

    /// Registers the given decoder.
    public func register<Decoder: ImageDecoderRegistering>(_ decoder: Decoder.Type) {
        register { context in
            if context.isCompleted {
                return decoder.init(data: context.data, context: context)
            } else {
                return decoder.init(partiallyDownloadedData: context.data, context: context)
            }
        }
    }

    /// Registers a decoder to be used in a given decoding context. The closure
    /// is going to be executed before all other already registered closures.
    public func register(_ match: @escaping (ImageDecodingContext) -> ImageDecoding?) {
        matches.insert(Match(closure: match), at: 0)
    }

    /// Removes all registered decoders.
    public func clear() {
        matches = []
    }
}

/// Image decoding context used when selecting which decoder to use.
public struct ImageDecodingContext {
    public let request: ImageRequest
    public let data: Data
    /// Returns `true` if the download was completed.
    public let isCompleted: Bool
    public let urlResponse: URLResponse?

    public init(request: ImageRequest, data: Data, isCompleted: Bool, urlResponse: URLResponse?) {
        self.request = request
        self.data = data
        self.isCompleted = isCompleted
        self.urlResponse = urlResponse
    }
}

// MARK: - ImageType

/// A uniform type identifier (UTI).
public struct ImageType: ExpressibleByStringLiteral, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public static let png: ImageType = "public.png"
    public static let jpeg: ImageType = "public.jpeg"
    public static let gif: ImageType = "com.compuserve.gif"
    /// HEIF (High Efficiency Image Format) by Apple.
    public static let heic: ImageType = "public.heic"

    /// WebP
    ///
    /// Native decoding support only available on the following platforms: macOS 11,
    /// iOS 14, watchOS 7, tvOS 14.
    public static let webp: ImageType = "public.webp"
}

public extension ImageType {
    /// Determines a type of the image based on the given data.
    init?(_ data: Data) {
        guard let type = ImageType.make(data) else {
            return nil
        }
        self = type
    }

    private static func make(_ data: Data) -> ImageType? {
        func _match(_ numbers: [UInt8?]) -> Bool {
            guard data.count >= numbers.count else {
                return false
            }
            return zip(numbers.indices, numbers).allSatisfy { index, number in
                guard let number = number else { return true }
                return data[index] == number
            }
        }

        // JPEG magic numbers https://en.wikipedia.org/wiki/JPEG
        if _match([0xFF, 0xD8, 0xFF]) { return .jpeg }

        // PNG Magic numbers https://en.wikipedia.org/wiki/Portable_Network_Graphics
        if _match([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }

        // GIF magic numbers https://en.wikipedia.org/wiki/GIF
        if _match([0x47, 0x49, 0x46]) { return .gif }

        // WebP magic numbers https://en.wikipedia.org/wiki/List_of_file_signatures
        if _match([0x52, 0x49, 0x46, 0x46, nil, nil, nil, nil, 0x57, 0x45, 0x42, 0x50]) { return .webp }

        // Either not enough data, or we just don't support this format.
        return nil
    }
}

// MARK: - ImageProperties

enum ImageProperties {}

// Keeping this private for now, not sure neither about the API, not the implementation.
extension ImageProperties {
    struct JPEG {
        public var isProgressive: Bool

        public init?(_ data: Data) {
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
