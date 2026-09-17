// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws the generated fixtures with Core Graphics and encodes them with
/// Image I/O.
///
/// Nothing here depends on the time, the screen, or a random source that
/// isn't seeded: a sRGB bitmap of a fixed size, shapes placed by a generator
/// seeded with the fixture, and text in one font. The same fixture is the same
/// bytes on every run on a given system, as long as it is drawn while nothing
/// else is: Core Graphics drew the same translucent shapes a little
/// differently when several threads drew at once, so ``DemoFixtureStore``
/// makes one fixture at a time. Another OS version may encode it differently,
/// which is why the Lab lists a digest of each one.
///
/// The drawing is cheap on purpose – a few hundred shapes, flat frames for
/// the animations – so that the first request for a fixture doesn't wait long
/// for it.
enum DemoFixtureRenderer {
    /// The encoded data of a generated fixture. Throws for a bundled one.
    static func data(for fixture: DemoFixture) throws -> Data {
        let data: Data? = switch fixture {
        case .photo(let index):
            jpeg(photo(index: index), isProgressive: false)
        case .jpeg:
            jpeg(landscape, isProgressive: false)
        case .progressiveJPEG:
            jpeg(landscape, isProgressive: true)
        case .largeJPEG:
            jpeg(picture(seed: 3, width: 4000, height: 3000, title: "12 MP", caption: "FIXTURE 4000×3000"), isProgressive: false)
        case .png:
            encode([graphic], type: .png)
        case .gif:
            gif(frameCount: 60, size: 400, delay: 0.03, title: "GIF")
        case .longGIF:
            gif(frameCount: 200, size: 300, delay: 0.05, title: "LONG GIF")
        case .apng:
            apng(frameCount: 20, size: 100, delay: 0.075)
        case .heic:
            encode(
                [picture(seed: 11, width: 1008, height: 756, title: "HEIC", caption: "FIXTURE 1008×756")],
                type: .heic,
                frameProperties: [kCGImageDestinationLossyCompressionQuality: 0.8]
            )
        case .webp, .animatedWebP, .video, .missing, .zoo:
            nil
        }
        guard let data else {
            throw DemoFixtureError.encodingFailed(fixture)
        }
        return data
    }

    // MARK: Pictures

    /// The stand-in for a photo: its index, large, over a picture.
    static func photo(index: Int) -> CGImage {
        let (width, height) = DemoFixture.photoSize(at: index)
        return picture(seed: index, width: width, height: height, title: "\(index)", caption: "FIXTURE \(width)×\(height)")
    }

    /// The picture behind ``DemoFixture/jpeg`` and
    /// ``DemoFixture/progressiveJPEG``: the two encodings are of the same
    /// pixels.
    private static var landscape: CGImage {
        picture(seed: 7, width: 1440, height: 960, title: "JPEG", caption: "FIXTURE 1440×960")
    }

    /// A diagonal gradient under a scatter of rings, with a title and a
    /// caption on a dark plate in the middle.
    ///
    /// The rings give the encoder detail to spend bytes on, so a stand-in is
    /// about the size of a photo on disk, and the scans of a progressive
    /// encoding sharpen visibly. There are at most 1,200 of them whatever the
    /// size, drawn larger on a larger canvas, which keeps a 12 MP picture
    /// under a tenth of a second.
    static func picture(seed: Int, width: Int, height: Int, title: String, caption: String) -> CGImage {
        let context = makeContext(width: width, height: height)
        let size = CGSize(width: width, height: height)
        let hue = (Double(seed) * 0.618034).truncatingRemainder(dividingBy: 1)

        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [color(hue: hue, saturation: 0.45, brightness: 0.95), color(hue: hue + 0.1, saturation: 0.8, brightness: 0.45)] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])

        var random = SeededRandom(seed: UInt64(seed))
        let area = size.width * size.height
        let count = min(Int(area / 900), 1200)
        let spacing = (area / CGFloat(count)).squareRoot()
        let outline = color(hue: hue + 0.5, saturation: 0.3, brightness: 1, alpha: 0.5)
        context.setLineWidth(max(1, spacing / 30))
        for _ in 0..<count {
            let radius = (0.5 + random.next() * 2.5) * 0.15 * spacing
            let center = CGPoint(x: random.next() * size.width, y: random.next() * size.height)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.setFillColor(color(hue: hue + random.next() * 0.3, saturation: 0.6, brightness: 0.4 + random.next() * 0.6, alpha: 0.35))
            context.fillEllipse(in: rect)
            context.setStrokeColor(outline)
            context.strokeEllipse(in: rect.insetBy(dx: radius * 0.3, dy: radius * 0.3))
        }

        let unit = min(size.width, size.height) * 0.42
        let plate = CGRect(x: size.width / 2 - unit * 0.9, y: size.height / 2 - unit * 0.45, width: unit * 1.8, height: unit * 0.9)
        context.setFillColor(black(alpha: 0.45))
        context.addPath(CGPath(roundedRect: plate, cornerWidth: unit * 0.12, cornerHeight: unit * 0.12, transform: nil))
        context.fillPath()
        draw(title, in: context, fontSize: unit * (title.count > 3 ? 0.36 : 0.6), center: CGPoint(x: plate.midX, y: plate.midY + unit * 0.08), color: white())
        draw(caption, in: context, fontSize: unit * 0.13, center: CGPoint(x: plate.midX, y: plate.minY + unit * 0.14), color: white(alpha: 0.8))
        return context.makeImage()!
    }

    /// A ring on a transparent background, for the PNG.
    private static var graphic: CGImage {
        let context = makeContext(width: 840, height: 510)
        context.setStrokeColor(color(hue: 0.58, saturation: 0.8, brightness: 0.9))
        context.setLineWidth(60)
        context.strokeEllipse(in: CGRect(x: 180, y: 15, width: 480, height: 480))
        context.setFillColor(color(hue: 0.58, saturation: 0.8, brightness: 0.9, alpha: 0.25))
        context.fillEllipse(in: CGRect(x: 210, y: 45, width: 420, height: 420))
        draw("PNG", in: context, fontSize: 120, center: CGPoint(x: 420, y: 275), color: black(alpha: 0.85))
        draw("FIXTURE 840×510 · ALPHA", in: context, fontSize: 24, center: CGPoint(x: 420, y: 170), color: black(alpha: 0.7))
        return context.makeImage()!
    }

    /// A frame of an animation: a flat color that turns through the hues over
    /// the loop, the frame's number, and a bar that fills to the last frame.
    /// Flat colors keep the GIF encoder's palettes small and quick.
    static func frame(_ index: Int, of count: Int, width: Int, height: Int, title: String) -> CGImage {
        let context = makeContext(width: width, height: height)
        let size = CGSize(width: width, height: height)
        let unit = min(size.width, size.height)
        context.setFillColor(color(hue: Double(index) / Double(count), saturation: 0.55, brightness: 0.8))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(black())
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: unit * 0.06))
        context.setFillColor(white())
        context.fill(CGRect(x: 0, y: 0, width: size.width * CGFloat(index + 1) / CGFloat(count), height: unit * 0.06))
        draw(title, in: context, fontSize: unit * 0.08, center: CGPoint(x: size.width / 2, y: size.height - unit * 0.12), color: white(alpha: 0.85))
        draw("\(index + 1)", in: context, fontSize: unit * 0.36, center: CGPoint(x: size.width / 2, y: size.height / 2 + unit * 0.04), color: white())
        draw("of \(count)", in: context, fontSize: unit * 0.09, center: CGPoint(x: size.width / 2, y: size.height / 2 - unit * 0.22), color: white())
        return context.makeImage()!
    }

    /// A frame of the bouncing ball, on a transparent background.
    private static func ball(_ index: Int, of count: Int, size: Int) -> CGImage {
        let context = makeContext(width: size, height: size)
        let side = CGFloat(size)
        let time = Double(index) / Double(count)
        let radius = side * 0.14
        let bottom = side * 0.12 + side * 0.6 * (1 - pow(2 * time - 1, 2))
        context.setFillColor(black(alpha: 0.25))
        context.fillEllipse(in: CGRect(x: side / 2 - radius, y: side * 0.04, width: radius * 2, height: radius * 0.5))
        context.setFillColor(color(hue: time, saturation: 0.8, brightness: 0.95))
        context.fillEllipse(in: CGRect(x: side / 2 - radius, y: bottom, width: radius * 2, height: radius * 2))
        return context.makeImage()!
    }

    // MARK: Encoding

    private static func jpeg(_ image: CGImage, isProgressive: Bool) -> Data? {
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        if isProgressive {
            properties[kCGImagePropertyJFIFDictionary] = [kCGImagePropertyJFIFIsProgressive: true]
        }
        return encode([image], type: .jpeg, frameProperties: properties)
    }

    private static func gif(frameCount: Int, size: Int, delay: Double, title: String) -> Data? {
        let frames = (0..<frameCount).map { frame($0, of: frameCount, width: size, height: size, title: title) }
        return encode(
            frames,
            type: .gif,
            properties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]],
            frameProperties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]]
        )
    }

    private static func apng(frameCount: Int, size: Int, delay: Double) -> Data? {
        let frames = (0..<frameCount).map { ball($0, of: frameCount, size: size) }
        return encode(
            frames,
            type: .png,
            properties: [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]],
            frameProperties: [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]]
        )
    }

    static func encode(_ images: [CGImage], type: UTType, properties: [CFString: Any] = [:], frameProperties: [CFString: Any] = [:]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, images.count, nil) else {
            return nil
        }
        CGImageDestinationSetProperties(destination, properties as CFDictionary)
        for image in images {
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: Progressive JPEG

    /// Where each scan of a JPEG starts: the offset of every start-of-scan
    /// (SOS) marker, in order. A baseline JPEG has one.
    ///
    /// Data cut right before a scan's marker holds every scan before it in
    /// full, which is what an incremental decoder needs to show them. The
    /// walk follows the marker segments by their lengths, and skips a scan's
    /// entropy-coded data up to the next marker: a `0xFF` there is followed by
    /// a stuffed zero or a restart marker.
    static func scanOffsets(inJPEG data: Data) -> [Int] {
        let bytes = [UInt8](data)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else {
            return []
        }
        var offsets: [Int] = []
        var index = 2
        while index + 3 < bytes.count {
            guard bytes[index] == 0xFF else {
                index += 1
                continue
            }
            let marker = bytes[index + 1]
            if marker == 0xD9 { break } // End of image
            if marker == 0xFF { // Fill byte
                index += 1
                continue
            }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard marker == 0xDA else {
                index += 2 + length
                continue
            }
            offsets.append(index)
            index += 2 + length
            while index + 1 < bytes.count {
                if bytes[index] == 0xFF, bytes[index + 1] != 0x00, !(0xD0...0xD7).contains(bytes[index + 1]) {
                    break
                }
                index += 1
            }
        }
        return offsets
    }

    // MARK: Drawing

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A bitmap context, cleared: its memory isn't documented to start out
    /// zeroed, and the transparent fixtures show what is under them.
    private static func makeContext(width: Int, height: Int) -> CGContext {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    private static func draw(_ text: String, in context: CGContext, fontSize: CGFloat, center: CGPoint, color: CGColor) {
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.textPosition = CGPoint(x: center.x - bounds.width / 2 - bounds.minX, y: center.y - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, context)
    }

    private static func color(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) -> CGColor {
        let hue = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let sector = Int(hue)
        let fraction = hue - Double(sector)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))
        let (red, green, blue) = switch sector {
        case 0: (brightness, t, p)
        case 1: (q, brightness, p)
        case 2: (p, brightness, t)
        case 3: (p, q, brightness)
        case 4: (t, p, brightness)
        default: (brightness, p, q)
        }
        return CGColor(colorSpace: colorSpace, components: [CGFloat(red), CGFloat(green), CGFloat(blue), CGFloat(alpha)])!
    }

    private static func white(alpha: Double = 1) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [1, 1, 1, CGFloat(alpha)])!
    }

    private static func black(alpha: Double = 1) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [0, 0, 0, CGFloat(alpha)])!
    }
}

/// SplitMix64: a few lines of arithmetic, and the same sequence for the same
/// seed on every platform, which `SystemRandomNumberGenerator` isn't.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 1
    }

    /// A number from 0 up to 1.
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
