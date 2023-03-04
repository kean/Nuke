// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation
import CoreGraphics
import ImageIO

#if !os(macOS)
import UIKit
#else
import AppKit
#endif

extension ImageEncoders {
    /// An Image I/O based encoder.
    ///
    /// Image I/O is a system framework that allows applications to read and
    /// write most image file formats. This framework offers high efficiency,
    /// color management, and access to image metadata.
    public struct ImageIO: ImageEncoding {
        public let type: AssetType
        public let compressionRatio: Float

        /// - parameter format: The output format. Make sure that the format is
        /// supported on the current hardware.s
        /// - parameter compressionRatio: 0.8 by default.
        public init(type: AssetType, compressionRatio: Float = 0.8) {
            self.type = type
            self.compressionRatio = compressionRatio
        }

        @Atomic private static var availability = [AssetType: Bool]()

        /// Returns `true` if the encoding is available for the given format on
        /// the current hardware. Some of the most recent formats might not be
        /// available so its best to check before using them.
        public static func isSupported(type: AssetType) -> Bool {
            if let isAvailable = availability[type] {
                return isAvailable
            }
            let isAvailable = CGImageDestinationCreateWithData(
                NSMutableData() as CFMutableData, type.rawValue as CFString, 1, nil
            ) != nil
            availability[type] = isAvailable
            return isAvailable
        }

        public func encode(_ image: PlatformImage) -> Data? {
            let data = NSMutableData()
            var options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: compressionRatio
            ]
#if canImport(UIKit)
            options[kCGImagePropertyOrientation] = CGImagePropertyOrientation(image.imageOrientation).rawValue
#endif
            guard let source = image.cgImage,
                let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.rawValue as CFString, 1, nil) else {
                    return nil
            }
            CGImageDestinationAddImage(destination, source, options as CFDictionary)
            CGImageDestinationFinalize(destination)
            return data as Data
        }
    }
}
