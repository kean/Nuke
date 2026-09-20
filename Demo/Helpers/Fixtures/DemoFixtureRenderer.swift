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
/// which is why the store logs a digest of each one.
///
/// The drawing is cheap on purpose – a few hundred shapes, flat frames for
/// the animations – so that the first request for a fixture doesn't wait long
/// for it.
enum DemoFixtureRenderer {
    /// The encoded data of a generated fixture. Throws for a bundled one.
    static func data(for fixture: DemoFixture) throws -> Data {
        let data: Data? = switch fixture {
        case .photo(let index):
            jpeg(photo(index: index))
        case .largeJPEG:
            jpeg(picture(seed: 3, width: 4000, height: 3000, title: "12 MP", caption: "FIXTURE 4000×3000"))
        case .gif:
            gif(frameCount: 60, size: 400, delay: 0.03, title: "GIF")
        case .longGIF:
            gif(frameCount: 200, size: 300, delay: 0.05, title: "LONG GIF")
        case .apng:
            apng(frameCount: 20, size: 100, delay: 0.075)
        case .mixedDelayGIF:
            mixedDelayGIF
        case .animatedWebP, .nukePix, .truncatedNukePix:
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

    /// A diagonal gradient under a scatter of rings, with a title and a
    /// caption on a dark plate in the middle.
    ///
    /// The rings give the encoder detail to spend bytes on, so a stand-in is
    /// about the size of a photo on disk. There are at most 1,200 of them
    /// whatever the size, drawn larger on a larger canvas, which keeps a
    /// 12 MP picture under a tenth of a second.
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

        var random = DemoRandomNumberGenerator(seed: UInt64(seed) &+ 1)
        let area = size.width * size.height
        let count = min(Int(area / 900), 1200)
        let spacing = (area / CGFloat(count)).squareRoot()
        let outline = color(hue: hue + 0.5, saturation: 0.3, brightness: 1, alpha: 0.5)
        context.setLineWidth(max(1, spacing / 30))
        for _ in 0..<count {
            let radius = (0.5 + random.nextUnit() * 2.5) * 0.15 * spacing
            let center = CGPoint(x: random.nextUnit() * size.width, y: random.nextUnit() * size.height)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.setFillColor(color(hue: hue + random.nextUnit() * 0.3, saturation: 0.6, brightness: 0.4 + random.nextUnit() * 0.6, alpha: 0.35))
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

    private static func jpeg(_ image: CGImage) -> Data? {
        encode([image], type: .jpeg, frameProperties: [kCGImageDestinationLossyCompressionQuality: 0.8])
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

    /// Four frames of 0, 10, 20, and 500 ms. Image I/O reads the first two as
    /// 100 ms, the way browsers do, so the delay map has something to show.
    private static var mixedDelayGIF: Data? {
        let delays: [Double] = [0, 0.01, 0.02, 0.5]
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, delays.count, nil) else {
            return nil
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (index, delay) in delays.enumerated() {
            let image = frame(index, of: delays.count, width: 96, height: 96, title: "MIXED")
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        return CGImageDestinationFinalize(destination) ? data as Data : nil
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
