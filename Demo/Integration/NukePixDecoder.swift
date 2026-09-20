// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import UIKit

/// A decoder for NukePix, a toy image format made up for the Custom Decoder
/// screen: a palette, and runs of pixels in it, behind a four-byte
/// signature.
///
/// ```
/// offset   bytes   field
/// 0        4       "NUKE"
/// 4        1       version: 1
/// 5        1       width
/// 6        1       height
/// 7        1       colors in the palette: N
/// 8        4 × N   the palette: red, green, blue, alpha
/// 8 + 4N   2 × …   runs: a length and a color, row by row
/// ```
///
/// It is what a decoder for any format the system can't read looks like –
/// AVIF on an old OS, BlurHash, a format of an app's own: an initializer that
/// takes or passes on the data from its first bytes, and a `decode(_:)` that
/// turns the data into a `CGImage`. Registered, it is asked before the
/// decoders registered earlier, `ImageDecoders.Default` included:
///
/// ```swift
/// ImageDecoderRegistry.shared.register(NukePixDecoder.init)
/// ```
///
/// Written to be read and copied: the Custom Decoder screen shows this code
/// in its info sheet.
struct NukePixDecoder: ImageDecoding {
    static let signature = Data("NUKE".utf8)
    static let type = AssetType(rawValue: "com.github.kean.nukepix")

    /// Takes any data that starts with the signature, and passes on the rest.
    ///
    /// It doesn't look at `context.isCompleted`. With progressive decoding
    /// on, the pipeline asks as soon as the first bytes arrive and keeps the
    /// decoder it gets for the whole download: passing on a partial file
    /// would hand all of it to `ImageDecoders.Default`, which can't read it.
    /// Having no previews to offer, it leaves
    /// `decodePartiallyDownloadedData(_:)` to its default, which returns
    /// `nil`.
    init?(context: ImageDecodingContext) {
        guard context.data.starts(with: Self.signature) else {
            return nil
        }
    }

    /// `false`: a few kilobytes of runs decode in microseconds, on the
    /// pipeline's actor, with no hop to the decoding queue.
    var isAsynchronous: Bool { false }

    func decode(_ data: Data) throws -> ImageContainer {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else {
            throw Error.missingPixels(expected: 1, found: 0)
        }
        guard bytes[4] == 1 else {
            throw Error.unsupportedVersion(bytes[4])
        }
        let width = Int(bytes[5])
        let height = Int(bytes[6])
        let colorCount = Int(bytes[7])
        let runs = 8 + colorCount * 4
        guard bytes.count >= runs else {
            throw Error.missingPixels(expected: width * height, found: 0)
        }

        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        var offset = runs
        while offset + 1 < bytes.count, pixels.count < width * height * 4 {
            let length = Int(bytes[offset])
            let color = Int(bytes[offset + 1])
            guard color < colorCount else {
                throw Error.colorOutOfRange(color)
            }
            let rgba = bytes[(8 + color * 4)..<(12 + color * 4)]
            for _ in 0..<length {
                pixels.append(contentsOf: rgba)
            }
            offset += 2
        }
        guard width > 0, height > 0, pixels.count == width * height * 4 else {
            throw Error.missingPixels(expected: width * height, found: pixels.count / 4)
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw Error.missingPixels(expected: width * height, found: 0)
        }
        return ImageContainer(image: UIImage(cgImage: image), type: Self.type)
    }

    /// Why a NukePix file didn't decode. The pipeline passes it on as the
    /// `error` of `ImagePipeline.Error.decodingFailed`.
    enum Error: Swift.Error, CustomStringConvertible {
        case unsupportedVersion(UInt8)
        /// The runs ended before the image did: a file cut short.
        case missingPixels(expected: Int, found: Int)
        case colorOutOfRange(Int)

        var description: String {
            switch self {
            case .unsupportedVersion(let version): "unsupportedVersion(\(version))"
            case let .missingPixels(expected, found): "missingPixels(expected: \(expected), found: \(found))"
            case .colorOutOfRange(let color): "colorOutOfRange(\(color))"
            }
        }
    }
}

// MARK: - Writing

/// Writes the NukePix files the Custom Decoder screen loads, which the
/// fixture loader serves: the NUKE badge, and a copy of it cut short.
enum NukePixWriter {
    /// The badge: "NUKE" in white, with a shadow, on the logo's gradient, in
    /// a rounded rectangle. 56×26, in 874 bytes.
    static func badge() -> Data {
        let width = 56
        let height = 26
        let scale = 2
        let origin = (x: 5, y: 6)

        // 0 is clear and 1 white; each row has a color of the gradient and a
        // darker one for the shadow.
        var palette: [[UInt8]] = [[0, 0, 0, 0], [246, 246, 246, 255]]
        let top: [Double] = [255, 45, 100]
        let bottom: [Double] = [255, 160, 70]
        for row in 0..<height {
            let t = Double(row) / Double(height - 1)
            let color = zip(top, bottom).map { $0 + ($1 - $0) * t }
            palette.append(color.map { UInt8($0.rounded()) } + [255])
            palette.append(color.map { UInt8(($0 * 0.72).rounded()) } + [255])
        }

        // The letters, 5×7 each, a column apart, drawn at twice the size.
        var isLetter = Array(repeating: false, count: width * height)
        for (index, glyph) in [glyphN, glyphU, glyphK, glyphE].enumerated() {
            for (y, line) in glyph.enumerated() {
                for (x, character) in line.enumerated() where character == "X" {
                    for dy in 0..<scale {
                        for dx in 0..<scale {
                            let px = origin.x + (index * 6 + x) * scale + dx
                            let py = origin.y + y * scale + dy
                            isLetter[py * width + px] = true
                        }
                    }
                }
            }
        }

        var colors = [UInt8]()
        for y in 0..<height {
            // The corners, rounded to a radius of four pixels.
            let inset = [2, 1, 0][min(y, height - 1 - y, 2)]
            for x in 0..<width {
                if x < inset || x >= width - inset {
                    colors.append(0)
                } else if isLetter[y * width + x] {
                    colors.append(1)
                } else if x > 0, y > 0, isLetter[(y - 1) * width + (x - 1)] {
                    colors.append(UInt8(2 + y * 2 + 1))
                } else {
                    colors.append(UInt8(2 + y * 2))
                }
            }
        }
        return data(width: width, height: height, palette: palette, colors: colors)
    }

    /// The badge with the last 40% of its bytes missing: the signature and
    /// the palette, and too few runs.
    static func truncatedBadge() -> Data {
        let badge = badge()
        return badge.prefix(badge.count * 6 / 10)
    }

    /// A NukePix file of the colors, one palette index per pixel, row by row.
    static func data(width: Int, height: Int, palette: [[UInt8]], colors: [UInt8]) -> Data {
        var data = NukePixDecoder.signature
        data.append(contentsOf: [1, UInt8(width), UInt8(height), UInt8(palette.count)])
        for color in palette {
            data.append(contentsOf: color)
        }
        var index = 0
        while index < colors.count {
            let color = colors[index]
            var length = 1
            while index + length < colors.count, colors[index + length] == color, length < 255 {
                length += 1
            }
            data.append(contentsOf: [UInt8(length), color])
            index += length
        }
        return data
    }

    private static let glyphN = [
        "X...X",
        "X...X",
        "XX..X",
        "X.X.X",
        "X..XX",
        "X...X",
        "X...X"
    ]

    private static let glyphU = [
        "X...X",
        "X...X",
        "X...X",
        "X...X",
        "X...X",
        "X...X",
        ".XXX."
    ]

    private static let glyphK = [
        "X...X",
        "X..X.",
        "X.X..",
        "XX...",
        "X.X..",
        "X..X.",
        "X...X"
    ]

    private static let glyphE = [
        "XXXXX",
        "X....",
        "X....",
        "XXXX.",
        "X....",
        "X....",
        "XXXXX"
    ]
}
