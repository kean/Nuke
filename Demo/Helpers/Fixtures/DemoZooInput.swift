// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation

/// An input of the Fixture Zoo: a file the decoders should survive, from an
/// image at the edge of its format to one that isn't an image at all.
///
/// Each one is served by ``DemoFixtureLoader`` as ``DemoFixture/zoo(_:)``, at
/// `demo-fixture://nuke/zoo-<name>`, so that it reaches the decoders the way a
/// download does: through a data loader, the decoder registry, and
/// decompression.
///
/// Where the bytes come from, so that each one can be traced:
/// - Six files copied from `Tests/Resources` into `Resources/Zoo`, renamed
///   with the `zoo-` prefix because the bundle is flat: `animated.avif`,
///   `animated.webp` (served patched, see ``zeroDelayWebP``),
///   `grayscale.jpeg`, `image-p3.jpg`, `right-orientation.jpeg`, and
///   `fixture.ico`.
/// - `animated.heics`, which the demo already ships, and the first quarter of
///   `fixture-video.mp4` for ``truncatedVideo``.
/// - Everything else is made by ``DemoZooRenderer`` the first time a load
///   asks for it: drawn with ``DemoFixtureRenderer``, encoded with Image I/O,
///   then cut short or patched where the input is damaged on purpose, or
///   written byte by byte where Image I/O wouldn't write it.
enum DemoZooInput: String, CaseIterable, Sendable {
    // Unusual, but valid
    case onePixel = "1x1.png"
    case hugeCanvas = "canvas-20000.png"
    case cmykJPEG = "cmyk.jpeg"
    case sixteenBitPNG = "16-bit.png"
    case grayscaleJPEG = "grayscale.jpeg"
    case displayP3JPEG = "display-p3.jpg"
    case rotatedJPEG = "orientation-6.jpeg"
    case mirroredJPEG = "orientation-5.jpeg"
    case icon = "icon.ico"
    case heic = "still.heic"

    // Animations
    case zeroDelayGIF = "zero-delay.gif"
    case mixedDelayGIF = "mixed-delay.gif"
    case singleFrameGIF = "one-frame.gif"
    case zeroFrameAPNG = "zero-frames.png"
    case missingFramesAPNG = "missing-frames.png"
    case zeroDelayWebP = "zero-delay.webp"
    case heics = "animated.heics"
    case avis = "animated.avif"

    // Damaged
    case truncatedGIF = "truncated.gif"
    case truncatedJPEG = "truncated.jpeg"
    case corruptPNG = "corrupt.png"
    case headerOnlyPNG = "header-only.png"
    case jpegMagic = "jpeg-magic.jpeg"
    case truncatedVideo = "truncated.mp4"

    // Not images
    case empty = "empty"
    case randomBytes = "random.bin"
    case errorPage = "error-page.html"
    case svg = "vector.svg"
    case pdf = "document.pdf"
    case textAsJPEG = "not-a-photo.jpg"

    /// The groups the zoo shows its inputs in.
    enum Group: CaseIterable, Sendable {
        case unusual
        case animations
        case damaged
        case notImages

        var title: String {
            switch self {
            case .unusual: "Unusual, but Valid"
            case .animations: "Animations"
            case .damaged: "Damaged"
            case .notImages: "Not Images"
            }
        }

        var inputs: [DemoZooInput] {
            DemoZooInput.allCases.filter { $0.group == self }
        }
    }

    var group: Group {
        switch self {
        case .onePixel, .hugeCanvas, .cmykJPEG, .sixteenBitPNG, .grayscaleJPEG, .displayP3JPEG, .rotatedJPEG, .mirroredJPEG, .icon, .heic: .unusual
        case .zeroDelayGIF, .mixedDelayGIF, .singleFrameGIF, .zeroFrameAPNG, .missingFramesAPNG, .zeroDelayWebP, .heics, .avis: .animations
        case .truncatedGIF, .truncatedJPEG, .corruptPNG, .headerOnlyPNG, .jpegMagic, .truncatedVideo: .damaged
        case .empty, .randomBytes, .errorPage, .svg, .pdf, .textAsJPEG: .notImages
        }
    }

    /// The name of the file, the last component of its URL.
    var fileName: String { rawValue }

    var title: String {
        switch self {
        case .onePixel: "1×1"
        case .hugeCanvas: "20,000 px canvas"
        case .cmykJPEG: "CMYK JPEG"
        case .sixteenBitPNG: "16-bit PNG"
        case .grayscaleJPEG: "Grayscale JPEG"
        case .displayP3JPEG: "Display P3 JPEG"
        case .rotatedJPEG: "EXIF rotated"
        case .mirroredJPEG: "EXIF mirrored"
        case .icon: "ICO"
        case .heic: "HEIC"
        case .zeroDelayGIF: "GIF, 0 ms delays"
        case .mixedDelayGIF: "GIF, mixed delays"
        case .singleFrameGIF: "GIF, one frame"
        case .zeroFrameAPNG: "APNG, zero frames"
        case .missingFramesAPNG: "APNG, frames missing"
        case .zeroDelayWebP: "WebP, 0 ms delays"
        case .heics: "HEICS"
        case .avis: "AVIS"
        case .truncatedGIF: "Truncated GIF"
        case .truncatedJPEG: "Truncated JPEG"
        case .corruptPNG: "Corrupt PNG"
        case .headerOnlyPNG: "PNG header only"
        case .jpegMagic: "JPEG magic, no JPEG"
        case .truncatedVideo: "Truncated MP4"
        case .empty: "Empty"
        case .randomBytes: "Random bytes"
        case .errorPage: "HTML error page"
        case .svg: "SVG"
        case .pdf: "PDF"
        case .textAsJPEG: "Text named .jpg"
        }
    }

    /// What the file is, and where it comes from.
    var summary: String {
        switch self {
        case .onePixel: "A single opaque pixel. Generated."
        case .hugeCanvas: "20,000×20,000 in one palette color: 48 KB on disk, a 1.5 GB bitmap decoded. Written byte by byte."
        case .cmykJPEG: "160×120, four channels with no alpha. Generated."
        case .sixteenBitPNG: "160×120, 16 bits a channel. Generated."
        case .grayscaleJPEG: "200×200, one channel, a Gray Gamma 2.2 profile. From Tests/Resources."
        case .displayP3JPEG: "600×400 with a Display P3 profile. From Tests/Resources."
        case .rotatedJPEG: "480×640 stored, EXIF orientation 6: shown 640×480. From Tests/Resources."
        case .mirroredJPEG: "240×160 stored, EXIF orientation 5, drawn so that it reads upright once applied. Generated."
        case .icon: "A 32×32 Windows icon. From Tests/Resources."
        case .heic: "160×120 HEIF still, encoded by this system. Generated."
        case .zeroDelayGIF: "8 frames that each ask for 0 ms. Generated."
        case .mixedDelayGIF: "4 frames of 0, 10, 20, and 500 ms. Generated."
        case .singleFrameGIF: "A GIF with one frame: the header says GIF, which Nuke treats as animated. Generated."
        case .zeroFrameAPNG: "An APNG whose animation chunk says it has 0 frames. Patched."
        case .missingFramesAPNG: "An APNG that says 8 frames and holds only the first. Patched: Image I/O still counts 8."
        case .zeroDelayWebP: "4 frames of 8×8, their 100 ms patched to 0. From Tests/Resources."
        case .heics: "400×400, 30 frames of 50 ms, led by the msf1 brand. The demo's own."
        case .avis: "8×8, 3 frames of 250, 50, and 200 ms. From Tests/Resources."
        case .truncatedGIF: "The first half of a 12-frame GIF. Generated."
        case .truncatedJPEG: "The first 40% of a 320×240 baseline JPEG. Generated."
        case .corruptPNG: "A 160×120 PNG with its compressed pixels scrambled, the checksums fixed up. Generated."
        case .headerOnlyPNG: "A PNG signature and its header chunk, nothing after. Generated."
        case .jpegMagic: "The three bytes a JPEG starts with, then 2 KB of noise. Generated."
        case .truncatedVideo: "The first quarter of the bundled 2 s MP4."
        case .empty: "A 200 response with no body."
        case .randomBytes: "4 KB of seeded noise."
        case .errorPage: "A 404 page, as a misconfigured server returns it, typed text/html."
        case .svg: "A vector image, typed image/svg+xml."
        case .pdf: "A one-page PDF with a filled square. Written by hand, so it has no date in it."
        case .textAsJPEG: "A sentence of text, served as image/jpeg."
        }
    }

    /// The MIME type the fixture loader reports: what a server would say,
    /// right or wrong.
    var mimeType: String {
        switch self {
        case .onePixel, .hugeCanvas, .sixteenBitPNG, .zeroFrameAPNG, .missingFramesAPNG, .corruptPNG, .headerOnlyPNG: "image/png"
        case .cmykJPEG, .grayscaleJPEG, .displayP3JPEG, .rotatedJPEG, .mirroredJPEG, .truncatedJPEG, .jpegMagic, .textAsJPEG: "image/jpeg"
        case .icon: "image/vnd.microsoft.icon"
        case .heic: "image/heic"
        case .zeroDelayGIF, .mixedDelayGIF, .singleFrameGIF, .truncatedGIF: "image/gif"
        case .zeroDelayWebP: "image/webp"
        case .heics: "image/heic-sequence"
        case .avis: "image/avif"
        case .truncatedVideo: "video/mp4"
        case .empty, .randomBytes: "application/octet-stream"
        case .errorPage: "text/html"
        case .svg: "image/svg+xml"
        case .pdf: "application/pdf"
        }
    }

    /// Whether the bytes are read from the app bundle rather than made.
    var isBundled: Bool {
        switch self {
        case .grayscaleJPEG, .displayP3JPEG, .rotatedJPEG, .icon, .zeroDelayWebP, .heics, .avis, .truncatedVideo: true
        default: false
        }
    }

    /// The longest side a default run decodes the input at, for an input
    /// that could take the app down decoded in full; `nil` for the rest.
    ///
    /// Decoded in full, the 20,000 px canvas is a 1.5 GB bitmap, more than a
    /// phone lets an app have. A thumbnail of it is still a full decode inside
    /// Image I/O, a few hundred megabytes at the peak, but it's gone once the
    /// thumbnail is made.
    var safeMaxPixelSize: CGFloat? {
        self == .hugeCanvas ? 512 : nil
    }

    /// What the pipeline should make of the input, where that is known.
    var expectation: DemoZooExpectation {
        switch self {
        case .onePixel: .decoded(size: (1, 1), frames: 1)
        case .hugeCanvas: .decoded(size: (20_000, 20_000), frames: 1)
        case .cmykJPEG, .sixteenBitPNG, .heic: .decoded(size: (160, 120), frames: 1)
        case .grayscaleJPEG: .decoded(size: (200, 200), frames: 1)
        case .displayP3JPEG: .decoded(size: (600, 400), frames: 1)
        case .rotatedJPEG: .decoded(size: (640, 480), frames: 1)
        case .mirroredJPEG: .decoded(size: (160, 240), frames: 1)
        case .icon: .decoded(size: (32, 32), frames: 1)
        // Below 11 ms, a delay plays as 100 ms, the way browsers play it.
        case .zeroDelayGIF: .decoded(size: (96, 96), frames: 8, delays: Array(repeating: 0.1, count: 8))
        case .mixedDelayGIF: .decoded(size: (96, 96), frames: 4, delays: [0.1, 0.1, 0.02, 0.5])
        case .singleFrameGIF: .decoded(size: (96, 96), frames: 1)
        // Image I/O counts the frames the animation chunk declares; the
        // player keeps the last frame it could decode.
        case .missingFramesAPNG: .decoded(size: (96, 96), frames: nil)
        case .zeroDelayWebP: .decoded(size: (8, 8), frames: 4, delays: Array(repeating: 0.1, count: 4))
        case .heics: .decoded(size: (400, 400), frames: 30, delays: Array(repeating: 0.05, count: 30))
        // Image I/O clamps the 50 ms frame to 100 ms unless it's read unclamped.
        case .avis: .decoded(size: (8, 8), frames: 3, delays: [0.25, 0.05, 0.2])
        // The APNG specification calls zero frames an error, and says to fall
        // back to the default image; Image I/O refuses the file instead.
        case .zeroFrameAPNG, .truncatedGIF, .truncatedJPEG, .corruptPNG: .survived
        case .headerOnlyPNG, .jpegMagic, .truncatedVideo: .refused
        case .empty, .randomBytes, .errorPage, .svg, .pdf, .textAsJPEG: .refused
        }
    }
}

/// What the pipeline should make of a ``DemoZooInput``: a verdict, and for an
/// image, its size and frames.
struct DemoZooExpectation: Sendable {
    enum Outcome: Sendable {
        case decoded
        case refused
        /// Either, as long as the app is still running.
        case either
    }

    let outcome: Outcome
    /// The size in pixels, with the EXIF orientation applied.
    var size: (width: Int, height: Int)?
    /// The number of frames: 1 for a still, which has no animation.
    var frames: Int?
    /// How long each frame should play, in seconds.
    var delays: [TimeInterval]?

    static func decoded(size: (Int, Int), frames: Int?, delays: [TimeInterval]? = nil) -> DemoZooExpectation {
        DemoZooExpectation(outcome: .decoded, size: size, frames: frames, delays: delays)
    }

    static let refused = DemoZooExpectation(outcome: .refused)

    /// Decoded or refused, whichever the system makes of it.
    static let survived = DemoZooExpectation(outcome: .either)

    /// The expectation in a few words, for a tile.
    var summary: String {
        switch outcome {
        case .refused:
            return "refused"
        case .either:
            return "decoded or refused"
        case .decoded:
            var parts = ["decoded"]
            if let size {
                parts.append("\(size.width)×\(size.height)")
            }
            if let frames {
                parts.append(frames == 1 ? "still" : "\(frames) frames")
            }
            if let delays {
                parts.append(demoDelayList(delays))
            }
            return parts.joined(separator: " · ")
        }
    }
}

/// Frame delays in whole milliseconds: `8 × 100ms` when they're all the same,
/// `100, 100, 20, 500ms` when they aren't.
func demoDelayList(_ delays: [TimeInterval]) -> String {
    let milliseconds = delays.map { Int(($0 * 1000).rounded()) }
    guard let first = milliseconds.first else {
        return "no frames"
    }
    if milliseconds.allSatisfy({ $0 == first }) {
        return "\(milliseconds.count) × \(first)ms"
    }
    let shown = milliseconds.prefix(6).map(String.init).joined(separator: ", ")
    return shown + (milliseconds.count > 6 ? "…ms" : "ms")
}
