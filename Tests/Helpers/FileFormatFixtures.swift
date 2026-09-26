// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO

/// Container headers built by hand, and files written by Image I/O.
///
/// A header built by hand says exactly what a test asserts on, including what
/// no encoder writes: a box size that lies, a brand in the wrong place, a
/// chunk too long to be real. A file Image I/O writes is the counterpart: the
/// bytes the system itself produces.
extension Test {
    /// An ISO base media file type (`ftyp`) box, the way HEIF, AVIF, MP4, and
    /// QuickTime files start: the box size, the box type, the major brand, a
    /// minor version, and the compatible brands.
    ///
    /// - parameter brands: The major brand, followed by the compatible ones.
    /// - parameter declaredSize: The box size to write in place of the actual
    ///   one.
    static func fileTypeBox(brands: [String], declaredSize: UInt32? = nil) -> Data {
        var payload = Data(brands[0].utf8) + Data(count: 4)
        for brand in brands.dropFirst() {
            payload += Data(brand.utf8)
        }
        return bigEndian(declaredSize ?? UInt32(8 + payload.count)) + Data("ftyp".utf8) + payload
    }

    /// A WebP header: the RIFF wrapper, the first chunk, and the byte the
    /// extended format (`VP8X`) keeps its feature flags in.
    static func webPHeader(chunk: String = "VP8X", flags: UInt8) -> Data {
        var data = Data("RIFF".utf8) + Data([0x20, 0x00, 0x00, 0x00]) + Data("WEBP".utf8)
        data += Data(chunk.utf8) + Data([0x0A, 0x00, 0x00, 0x00])
        data += Data([flags]) + Data(count: 9)
        return data
    }

    /// A PNG: the signature, then the given chunks.
    static func png(chunks: [(name: String, payload: Data)]) -> Data {
        chunks.reduce(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) { $0 + pngChunk($1.name, $1.payload) }
    }

    /// A PNG chunk: a length, a name, the payload, and a CRC the sniffer never
    /// checks.
    ///
    /// - parameter declaredLength: The length to write in place of the length
    ///   of the payload.
    static func pngChunk(_ name: String, _ payload: Data, declaredLength: UInt32? = nil) -> Data {
        bigEndian(declaredLength ?? UInt32(payload.count)) + Data(name.utf8) + payload + Data(count: 4)
    }

    /// Writes the images into one file of the given type, a frame or a page
    /// each, or returns `nil` if Image I/O on this platform can't write it.
    ///
    /// - parameter type: The uniform type identifier of the format.
    static func encode(_ images: [CGImage], as type: String) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, images.count, nil) else {
            return nil
        }
        for image in images {
            CGImageDestinationAddImage(destination, image, nil)
        }
        guard CGImageDestinationFinalize(destination), data.length > 0 else {
            return nil
        }
        return data as Data
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
