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

import ImageIO

// MARK: - ImageEncoding

public protocol ImageEncoding {
    func encode(image: PlatformImage) -> Data?
}

// MARK: - ImageEncoder

// Soft-deprecated in Nuke 8.5
public typealias ImageEncoder = ImageEncoders.Default

/// Image encoding context used when selecting which encoder to use.
public struct ImageEncodingContext {
    public let request: ImageRequest
    public let image: PlatformImage
    public let urlResponse: URLResponse?
}

// MARK: - ImageEncoders

public enum ImageEncoders {}

// MARK: - ImageEncoders.Default

public extension ImageEncoders {
    /// A default adaptive encoder which uses best encoder available depending
    /// on the input image and its configuration.
    struct Default: ImageEncoding {
        private let compressionQuality: CGFloat

        /// Set to `true` to switch to HEIF when it is available on the current hardware.
        ///
        /// - note: This is an experimental new feature, an API might change in the future.
        public static var _isHEIFPreferred = false

        init(compressionQuality: CGFloat = 0.8) {
            self.compressionQuality = compressionQuality
        }

        public func encode(image: PlatformImage) -> Data? {
            guard let cgImage = image.cgImage else {
                return nil
            }
            let type: ImageType
            if cgImage.isOpaque {
                if #available(iOS 11, macOS 10.13, tvOS 11, watchOS 4, *) {
                    if ImageEncoders.Default._isHEIFPreferred && ImageEncoders.ImageIO.isSupported(type: .heic) {
                        type = .heic
                    } else {
                        type = .jpeg
                    }
                } else {
                    type = .jpeg
                }
            } else {
                type = .png
            }
            let encoder = ImageEncoders.ImageIO(type: type, compressionRatio: Float(compressionQuality))
            return encoder.encode(image: image)
        }
    }
}

// MARK: - ImageEncoders.ImageIO

public extension ImageEncoders {
    /// An Image I/O based encoder.
    ///
    /// Image I/O is a system framework that allows applications to read and
    /// write most image file formats. This framework offers high efficiency,
    /// color management, and access to image metadata.
    struct ImageIO: ImageEncoding {
        public let type: ImageType
        public let compressionRatio: Float

        /// - parameter format: The output format. Make sure that the format is
        /// supported on the current hardware.s
        /// - parameter compressionRatio: 0.8 by default.
        public init(type: ImageType, compressionRatio: Float = 0.8) {
            self.type = type
            self.compressionRatio = compressionRatio
        }

        private static let lock = NSLock()
        private static var availability = [ImageType: Bool]()

        /// Retuns `true` if the encoding is available for the given format on
        /// the current hardware. Some of the most recent formats might not be
        /// available so its best to check before using them.
        public static func isSupported(type: ImageType) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if let isAvailable = availability[type] {
                return isAvailable
            }
            let isAvailable = CGImageDestinationCreateWithData(
                NSMutableData() as CFMutableData, type.rawValue as CFString, 1, nil
            ) != nil
            availability[type] = isAvailable
            return isAvailable
        }

        public func encode(image: PlatformImage) -> Data? {
            let data = NSMutableData()
            let options: NSDictionary = [
                kCGImageDestinationLossyCompressionQuality: compressionRatio
            ]
            guard let source = image.cgImage,
                let destination = CGImageDestinationCreateWithData(
                    data as CFMutableData, type.rawValue as CFString, 1, nil
                ) else {
                    return nil
            }
            CGImageDestinationAddImage(destination, source, options)
            CGImageDestinationFinalize(destination)
            return data as Data
        }
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
    /// HEIF (High Effeciency Image Format) by Apple.
    public static let heic: ImageType = "public.heic"
}
