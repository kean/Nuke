// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import UniformTypeIdentifiers

/// A uniform type identifier (UTI).
public struct AssetType: ExpressibleByStringLiteral, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    /// PNG (Portable Network Graphics).
    public static let png: AssetType = "public.png"

    /// JPEG.
    public static let jpeg: AssetType = "public.jpeg"

    /// GIF (Graphics Interchange Format).
    public static let gif: AssetType = "com.compuserve.gif"

    /// HEIF (High Efficiency Image Format) by Apple.
    public static let heic: AssetType = "public.heic"

    /// WebP.
    ///
    /// Native decoding support only available on the following platforms: macOS 11,
    /// iOS 14, watchOS 7, tvOS 14.
    public static let webp: AssetType = "org.webmproject.webp"

    /// MPEG-4 video.
    public static let mp4: AssetType = "public.mpeg-4"

    /// M4V video container developed by Apple, similar to MP4. May optionally
    /// be protected by DRM copy protection.
    public static let m4v: AssetType = "com.apple.m4v-video"

    /// QuickTime movie.
    public static let mov: AssetType = "com.apple.quicktime-movie"

    /// ICO (Windows icon format).
    public static let ico: AssetType = "com.microsoft.ico"

    /// BMP (Windows bitmap).
    public static let bmp: AssetType = "com.microsoft.bmp"

    /// TIFF (Tagged Image File Format).
    public static let tiff: AssetType = "public.tiff"

    /// JPEG 2000.
    public static let jpeg2000: AssetType = "public.jpeg-2000"

    /// JPEG XL.
    ///
    /// Native decoding support only available on the following platforms: macOS 14,
    /// iOS 17, watchOS 10, tvOS 17.
    public static let jxl: AssetType = "public.jpeg-xl"
}

extension AssetType {
    /// The uniform type that ``rawValue`` identifies, or `nil` if the system
    /// doesn't recognize the identifier.
    ///
    /// Use it to reach the metadata the system associates with the type:
    ///
    /// ```swift
    /// AssetType.png.utType?.preferredMIMEType // "image/png"
    /// ```
    ///
    /// - note: The system only recognizes identifiers that are declared either
    /// by itself or by one of the loaded bundles, so the property returns `nil`
    /// for custom types that a decoder attaches without declaring them.
    public var utType: UTType? {
        UTType(rawValue)
    }

    /// Initializes the asset type with the identifier of the given uniform type.
    public init(_ type: UTType) {
        self.init(rawValue: type.identifier)
    }
}

extension AssetType {
    /// Determines a type of the image based on the given data.
    public init?(_ data: Data) {
        guard let type = AssetType.make(data) else {
            return nil
        }
        self = type
    }

    private static func make(_ data: Data) -> AssetType? {
        func _match(_ numbers: [UInt8?], offset: Int = 0) -> Bool {
            guard data.count >= numbers.count + offset else {
                return false
            }
            return zip(numbers.indices, numbers).allSatisfy { index, number in
                guard let number else { return true }
                guard let index = data.index(data.startIndex, offsetBy: index + offset, limitedBy: data.endIndex) else {
                    return false
                }
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

        // ISO base media file format (HEIC, MP4, M4V, MOV): the `ftyp` box
        // starts at byte 4 and is followed by a four-character major brand that
        // identifies the flavor of the container.
        // https://en.wikipedia.org/wiki/ISO_base_media_file_format
        if _match([0x66, 0x74, 0x79, 0x70], offset: 4),
           let type = _makeISOBaseMedia(majorBrand: _string(at: 8, count: 4, in: data)) {
            return type
        }

        // ICO magic numbers https://en.wikipedia.org/wiki/ICO_(file_format)
        if _match([0x00, 0x00, 0x01, 0x00]) { return .ico }

        // JPEG 2000: either the JP2 signature box, or a raw codestream that
        // starts with the SOC and SIZ markers.
        // https://en.wikipedia.org/wiki/JPEG_2000
        if _match([0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, 0x87, 0x0A]) { return .jpeg2000 }
        if _match([0xFF, 0x4F, 0xFF, 0x51]) { return .jpeg2000 }

        // JPEG XL: either the container signature box, or a naked codestream.
        // https://en.wikipedia.org/wiki/JPEG_XL
        if _match([0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A]) { return .jxl }
        if _match([0xFF, 0x0A]) { return .jxl }

        // TIFF magic numbers: a byte-order mark ("II" or "MM") followed by 42
        // written in that order. https://en.wikipedia.org/wiki/TIFF
        if _match([0x49, 0x49, 0x2A, 0x00]) || _match([0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }

        // BMP magic numbers https://en.wikipedia.org/wiki/BMP_file_format
        if _match([0x42, 0x4D]) { return .bmp }

        // Either not enough data, or we just don't support this format.
        return nil
    }

    /// Returns the type of an ISO base media file with the given major brand,
    /// or `nil` if the brand is unknown or belongs to an unsupported format,
    /// such as HEIF (`mif1`), AVIF (`avif`), or MPEG-4 audio (`M4A `).
    ///
    /// The brands are registered at https://mp4ra.org/registered-types/brands.
    private static func _makeISOBaseMedia(majorBrand: String?) -> AssetType? {
        switch majorBrand {
        case "heic", "heix", "heim", "heis", "hevc", "hevx", "hevm", "hevs":
            return .heic
        case "isom", "iso2", "iso4", "iso5", "iso6", "mp41", "mp42", "mmp4", "avc1", "dash":
            return .mp4
        case "M4V ", "M4VH", "M4VP":
            return .m4v
        case "qt  ":
            return .mov
        default:
            return nil
        }
    }

    /// Decodes `count` bytes at the given offset as an ASCII string, or returns
    /// `nil` if the data is too short.
    private static func _string(at offset: Int, count: Int, in data: Data) -> String? {
        guard data.count >= offset + count else {
            return nil
        }
        let start = data.index(data.startIndex, offsetBy: offset)
        return String(decoding: data[start..<data.index(start, offsetBy: count)], as: UTF8.self)
    }
}
