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

    /// AVIF (AV1 Image File Format).
    ///
    /// Image I/O decodes AVIF on every supported platform. Encoding arrived
    /// later – check ``ImageEncoders/ImageIO/isSupported(type:)`` before using it.
    public static let avif: AssetType = "public.avif"
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

        // GIF magic numbers: "GIF" followed by one of the two version numbers
        // the format defines. https://en.wikipedia.org/wiki/GIF
        if _match([0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
            _match([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]) { return .gif }

        // WebP magic numbers https://en.wikipedia.org/wiki/List_of_file_signatures
        if _match([0x52, 0x49, 0x46, 0x46, nil, nil, nil, nil, 0x57, 0x45, 0x42, 0x50]) { return .webp }

        // ISO base media file format (HEIC, AVIF, MP4, M4V, MOV): the `ftyp`
        // box starts at byte 4 and is followed by the four-character brands
        // that identify the flavor of the container.
        // https://en.wikipedia.org/wiki/ISO_base_media_file_format
        if _match([0x66, 0x74, 0x79, 0x70], offset: 4),
           let type = _makeISOBaseMedia(data) {
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

    /// Returns the type of an ISO base media file, or `nil` if none of the
    /// brands it declares belongs to a known format, as for bare HEIF
    /// (`mif1`) or MPEG-4 audio (`M4A `).
    ///
    /// The major brand is only the first answer: a HEIC image sequence leads
    /// with `msf1`, which says that the file holds a sequence but not what
    /// codec its frames use. The codec is in the compatible brands that follow.
    private static func _makeISOBaseMedia(_ data: Data) -> AssetType? {
        for brand in _brands(in: data) {
            if let type = _makeISOBaseMedia(brand: brand) {
                return type
            }
        }
        return nil
    }

    /// The brands an ISO base media file declares: the major brand, then the
    /// compatible brands. The `ftyp` box is a size, its name, the major brand,
    /// a minor version, and then the compatible brands until the box ends.
    private static func _brands(in data: Data) -> [String] {
        // The major brand is read whatever the declared size says, so that a
        // file with a damaged size still names itself.
        let end = max(12, min(Int(_uint32(at: 0, in: data) ?? 0), data.count))
        var brands: [String] = []
        for offset in stride(from: 8, to: end, by: 4) where offset != 12 {
            guard let brand = _string(at: offset, count: 4, in: data) else { break }
            brands.append(brand)
        }
        return brands
    }

    /// The format a single ISO base media brand belongs to.
    ///
    /// The brands are registered at https://mp4ra.org/registered-types/brands.
    private static func _makeISOBaseMedia(brand: String) -> AssetType? {
        switch brand {
        case "heic", "heix", "heim", "heis", "hevc", "hevx", "hevm", "hevs":
            return .heic
        case "avif", "avis":
            return .avif
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

    /// Returns `true` if the data holds an animation.
    ///
    /// The answer comes from the container header rather than from Image I/O,
    /// which would parse the whole file to count the frames. The check is
    /// deliberately one-sided: a false positive costs a copy of the data that
    /// nothing reads, while a false negative would leave an animation stuck on
    /// its first frame.
    static func isAnimated(_ data: Data, type: AssetType?) -> Bool {
        switch type {
        // Every GIF gets its data attached, animated or not, which is
        // long-standing behavior.
        case .gif: true
        case .png: _isAnimatedPNG(data)
        case .webp: _isAnimatedWebP(data)
        case .heic, .avif: _isImageSequence(data)
        default: false
        }
    }

    /// An APNG is a PNG with an `acTL` chunk, which the format requires to
    /// appear before the first `IDAT`.
    private static func _isAnimatedPNG(_ data: Data) -> Bool {
        var offset = 8 // The signature
        while let length = _uint32(at: offset, in: data),
              let name = _string(at: offset + 4, count: 4, in: data) {
            switch name {
            case "acTL": return true
            case "IDAT": return false // The pixels start here: there is no `acTL`
            default: break
            }
            // A chunk is a length, a name, the payload, and a CRC. A length
            // that doesn't fit means the file is damaged, not that it animates.
            guard length <= UInt32(Int32.max) else { return false }
            offset += Int(length) + 12
        }
        return false
    }

    /// An animated WebP is an extended-format file – one that starts with a
    /// `VP8X` chunk – with the animation bit set in its feature flags.
    private static func _isAnimatedWebP(_ data: Data) -> Bool {
        guard _string(at: 12, count: 4, in: data) == "VP8X", data.count > 20 else {
            return false
        }
        let flags = data[data.index(data.startIndex, offsetBy: 20)]
        return flags & 0x02 != 0
    }

    /// An ISO base media file is an image sequence – an animated HEIC or AVIF –
    /// when one of the brands in its `ftyp` box says so.
    private static func _isImageSequence(_ data: Data) -> Bool {
        guard _string(at: 4, count: 4, in: data) == "ftyp" else {
            return false
        }
        // `msf1` is the generic image sequence brand, `hev*` its HEVC flavors,
        // and `avis` the AV1 one. The still image brands are absent by design.
        let sequenceBrands: Set<String> = ["msf1", "hevc", "hevx", "hevm", "hevs", "avis"]
        return _brands(in: data).contains(where: sequenceBrands.contains)
    }

    /// Decodes four big-endian bytes at the given offset, or returns `nil` if
    /// the data is too short.
    private static func _uint32(at offset: Int, in data: Data) -> UInt32? {
        guard offset >= 0, data.count >= offset + 4 else {
            return nil
        }
        let start = data.index(data.startIndex, offsetBy: offset)
        return data[start..<data.index(start, offsetBy: 4)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }
}
