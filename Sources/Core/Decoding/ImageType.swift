// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

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

    public static let mp4: ImageType = "public.mp4"
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
        func _match(_ numbers: [UInt8?], offset: Int = 0) -> Bool {
            guard data.count >= numbers.count else {
                return false
            }
            return zip(numbers.indices, numbers).allSatisfy { index, number in
                guard let number = number else { return true }
                guard (index + offset) < data.count else { return false }
                return data[index + offset] == number
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

        // TODO: extened support for other image formats
        // ftypisom - ISO Base Media file (MPEG-4) v1
        // There are a bunch of other ways to create MP4
        // https://www.garykessler.net/library/file_sigs.html
        if _match([0x66, 0x74, 0x79, 0x70], offset: 4) { return .mp4 }

        // Either not enough data, or we just don't support this format.
        return nil
    }
}
