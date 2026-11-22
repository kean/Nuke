// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import CoreGraphics
import ImageIO
import os

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

        /// - parameter type: The output format. Make sure that the format is
        /// supported on the current hardware.
        /// - parameter compressionRatio: 0.8 by default.
        public init(type: AssetType, compressionRatio: Float = 0.8) {
            self.type = type
            self.compressionRatio = compressionRatio
        }

        private static let availability = OSAllocatedUnfairLock<[AssetType: Bool]>(initialState: [:])

        /// Returns `true` if the encoding is available for the given format on
        /// the current hardware. Some of the most recent formats might not be
        /// available so its best to check before using them.
        public static func isSupported(type: AssetType) -> Bool {
            if let isAvailable = availability.withLock({ $0[type] }) {
                return isAvailable
            }
            let isAvailable = CGImageDestinationCreateWithData(
                NSMutableData() as CFMutableData, type.rawValue as CFString, 1, nil
            ) != nil
            availability.withLock { $0[type] = isAvailable }
            return isAvailable
        }

        public func encode(_ image: PlatformImage) -> Data? {
            guard let source = image.cgImage,
                let data = CFDataCreateMutable(nil, 0),
                  let destination = CGImageDestinationCreateWithData(data, type.rawValue as CFString, 1, nil) else {
                return nil
            }
            var options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: compressionRatio
            ]
#if canImport(UIKit)
            options[kCGImagePropertyOrientation] = CGImagePropertyOrientation(image.imageOrientation).rawValue
#else
            // `NSImage(data:)` sizes an image by its DPI, and a processed image
            // keeps the points per pixel of its source, so write them: without
            // them, a high-DPI image comes back from the disk cache at its pixel
            // size. One point per pixel is 72 DPI, which is what not writing it
            // means already.
            let size = image.size
            if size.width > 0, size.height > 0,
               CGFloat(source.width) != size.width || CGFloat(source.height) != size.height {
                options[kCGImagePropertyDPIWidth] = 72 * CGFloat(source.width) / size.width
                options[kCGImagePropertyDPIHeight] = 72 * CGFloat(source.height) / size.height
            }
#endif
            CGImageDestinationAddImage(destination, source, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                return nil
            }
            return data as Data
        }
    }
}
