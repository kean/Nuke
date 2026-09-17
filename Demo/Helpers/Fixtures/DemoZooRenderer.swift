// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Compression
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Makes the bytes of the Fixture Zoo's inputs.
///
/// The images are drawn with ``DemoFixtureRenderer`` and encoded with Image
/// I/O, so they are the same bytes on every run on a given system, and
/// ``DemoFixtureStore`` makes them one at a time for the same reason it makes
/// the other fixtures that way. The damaged ones are good files spoiled in a
/// fixed way: cut at a fixed fraction, patched at a known offset, or
/// scrambled with seeded noise.
///
/// Three are written byte by byte, because Image I/O wouldn't write them or
/// wouldn't write them small: the 20,000 px canvas, the PDF, and the PNG with
/// only a header.
enum DemoZooRenderer {
    /// The bytes of a zoo input.
    static func data(for input: DemoZooInput) throws -> Data {
        let data: Data? = switch input {
        case .onePixel:
            onePixel
        case .hugeCanvas:
            flatPNG(width: 20_000, height: 20_000)
        case .cmykJPEG:
            converted(picture("CMYK"), space: CGColorSpaceCreateDeviceCMYK(), bitsPerComponent: 8, alpha: .none, type: .jpeg)
        case .sixteenBitPNG:
            converted(picture("16 BIT"), space: CGColorSpace(name: CGColorSpace.sRGB)!, bitsPerComponent: 16, alpha: .noneSkipLast, type: .png)
        case .grayscaleJPEG:
            try bundled("zoo-grayscale", "jpeg")
        case .displayP3JPEG:
            try bundled("zoo-display-p3", "jpg")
        case .rotatedJPEG:
            try bundled("zoo-orientation-6", "jpeg")
        case .mirroredJPEG:
            transposedJPEG
        case .icon:
            try bundled("zoo-icon", "ico")
        case .heic:
            DemoFixtureRenderer.encode([picture("HEIC")], type: .heic)
        case .zeroDelayGIF:
            gif(title: "0 MS", delays: Array(repeating: 0, count: 8))
        case .mixedDelayGIF:
            gif(title: "MIXED", delays: [0, 0.01, 0.02, 0.5])
        case .singleFrameGIF:
            gif(title: "ONE", delays: [0.1])
        case .zeroFrameAPNG:
            apng.flatMap(withoutFrameCount)
        case .missingFramesAPNG:
            apng.flatMap(withoutFramesAfterFirst)
        case .zeroDelayWebP:
            withoutDelays(try bundled("zoo-animated", "webp"))
        case .heics:
            try bundled("animated", "heics")
        case .avis:
            try bundled("zoo-animated", "avif")
        case .truncatedGIF:
            gif(title: "CUT", delays: Array(repeating: 0.1, count: 12)).map { head($0, 1 / 2) }
        case .truncatedJPEG:
            jpeg(DemoFixtureRenderer.picture(seed: 23, width: 320, height: 240, title: "CUT", caption: "ZOO 320×240")).map { head($0, 2 / 5) }
        case .corruptPNG:
            DemoFixtureRenderer.encode([picture("PNG")], type: .png).flatMap(scrambled)
        case .headerOnlyPNG:
            png([header(width: 96, height: 96, bitDepth: 8, colorType: 6)])
        case .jpegMagic:
            Data([0xFF, 0xD8, 0xFF]) + noise(count: 2048, seed: 1)
        case .truncatedVideo:
            head(try bundled("fixture-video", "mp4"), 1 / 4)
        case .empty:
            Data()
        case .randomBytes:
            noise(count: 4096, seed: 2)
        case .errorPage:
            Data(errorPage.utf8)
        case .svg:
            Data(svg.utf8)
        case .pdf:
            pdf
        case .textAsJPEG:
            Data("This is not a photo. It is a line of text that a server sent as image/jpeg.\n".utf8)
        }
        guard let data else {
            throw DemoFixtureError.encodingFailed(.zoo(input))
        }
        return data
    }

    // MARK: Images

    /// A small picture with a title, the base of the converted stills.
    private static func picture(_ title: String) -> CGImage {
        DemoFixtureRenderer.picture(seed: 17, width: 160, height: 120, title: title, caption: "ZOO 160×120")
    }

    private static var onePixel: Data? {
        guard let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage().flatMap { DemoFixtureRenderer.encode([$0], type: .png) }
    }

    /// The image drawn again in another pixel format, which is what the
    /// encoder then writes: four channels for CMYK, 16 bits for a PNG.
    private static func converted(_ image: CGImage, space: CGColorSpace, bitsPerComponent: Int, alpha: CGImageAlphaInfo, type: UTType) -> Data? {
        var bitmapInfo = alpha.rawValue
        if bitsPerComponent == 16 {
            bitmapInfo |= CGBitmapInfo.byteOrder16Little.rawValue
        }
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: bitsPerComponent, bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage().flatMap { image in
            type == .jpeg ? jpeg(image) : DemoFixtureRenderer.encode([image], type: type)
        }
    }

    private static func jpeg(_ image: CGImage) -> Data? {
        DemoFixtureRenderer.encode([image], type: .jpeg, frameProperties: [kCGImageDestinationLossyCompressionQuality: 0.8])
    }

    /// A 160×240 picture stored transposed, 240×160, with EXIF orientation 5
    /// (`leftMirrored`), which is its own inverse: applied, the picture reads
    /// upright; ignored, it lies on its side, mirrored.
    private static var transposedJPEG: Data? {
        let upright = DemoFixtureRenderer.picture(seed: 29, width: 160, height: 240, title: "EXIF", caption: "ORIENTATION 5")
        guard let context = CGContext(data: nil, width: 240, height: 160, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        // A transpose in the top-left coordinates of the file is the
        // anti-diagonal flip in Core Graphics' bottom-left ones.
        context.concatenate(CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: 240, ty: 160))
        context.draw(upright, in: CGRect(x: 0, y: 0, width: 160, height: 240))
        return context.makeImage().flatMap {
            DemoFixtureRenderer.encode([$0], type: .jpeg, frameProperties: [
                kCGImageDestinationLossyCompressionQuality: 0.8,
                kCGImagePropertyOrientation: CGImagePropertyOrientation.leftMirrored.rawValue
            ])
        }
    }

    // MARK: Animations

    /// A 96×96 GIF that loops forever, with a delay of its own for each frame.
    private static func gif(title: String, delays: [TimeInterval]) -> Data? {
        let frames = delays.indices.map { DemoFixtureRenderer.frame($0, of: delays.count, width: 96, height: 96, title: title) }
        return encode(
            frames,
            type: .gif,
            properties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]],
            frameProperties: delays.map { [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: $0]] }
        )
    }

    /// A 96×96 APNG of 8 frames of 100 ms, the base of the two broken ones.
    private static var apng: Data? {
        let frames = (0..<8).map { DemoFixtureRenderer.frame($0, of: 8, width: 96, height: 96, title: "APNG") }
        return encode(
            frames,
            type: .png,
            properties: [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]],
            frameProperties: frames.map { _ in [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: 0.1]] }
        )
    }

    /// The APNG with `num_frames` in its `acTL` chunk set to zero.
    private static func withoutFrameCount(_ data: Data) -> Data? {
        guard var chunks = pngChunks(data),
              let index = chunks.firstIndex(where: { $0.type == "acTL" }) else {
            return nil
        }
        chunks[index].payload.replaceSubrange(0..<4, with: [0, 0, 0, 0])
        return png(chunks)
    }

    /// The APNG with every frame after the default image taken out, while
    /// its `acTL` chunk still counts them.
    private static func withoutFramesAfterFirst(_ data: Data) -> Data? {
        guard let chunks = pngChunks(data),
              let lastImageData = chunks.lastIndex(where: { $0.type == "IDAT" }) else {
            return nil
        }
        return png(chunks.enumerated().filter { index, chunk in
            index <= lastImageData || !["fcTL", "fdAT"].contains(chunk.type)
        }.map(\.element))
    }

    /// The WebP with the duration of every `ANMF` frame set to zero.
    ///
    /// A RIFF chunk is a four-character name, a little-endian size, and the
    /// payload, padded to an even length. An `ANMF` payload starts with the
    /// frame's position and size, three bytes each, then three bytes of
    /// duration.
    private static func withoutDelays(_ data: Data) -> Data? {
        var bytes = [UInt8](data)
        var offset = 12 // "RIFF", the size, "WEBP"
        var patched = 0
        while offset + 8 <= bytes.count {
            let name = String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
            let size = Int(bytes[offset + 4]) | Int(bytes[offset + 5]) << 8 | Int(bytes[offset + 6]) << 16 | Int(bytes[offset + 7]) << 24
            let payload = offset + 8
            if name == "ANMF", payload + 15 <= bytes.count {
                bytes.replaceSubrange(payload + 12..<payload + 15, with: [0, 0, 0])
                patched += 1
            }
            offset = payload + size + size % 2
        }
        return patched > 0 ? Data(bytes) : nil
    }

    /// Encodes the frames with properties of their own.
    private static func encode(_ images: [CGImage], type: UTType, properties: [CFString: Any], frameProperties: [[CFString: Any]]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, images.count, nil) else {
            return nil
        }
        CGImageDestinationSetProperties(destination, properties as CFDictionary)
        for (image, properties) in zip(images, frameProperties) {
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: Damage

    /// The PNG with the middle third of its compressed pixels replaced by
    /// noise, and its checksums fixed up, so that only the pixels are wrong.
    private static func scrambled(_ data: Data) -> Data? {
        guard var chunks = pngChunks(data),
              let index = chunks.firstIndex(where: { $0.type == "IDAT" }) else {
            return nil
        }
        let count = chunks[index].payload.count
        let range = count / 3..<count * 2 / 3
        chunks[index].payload.replaceSubrange(range, with: noise(count: range.count, seed: 3))
        return png(chunks)
    }

    /// The first `fraction` of the data.
    private static func head(_ data: Data, _ fraction: Double) -> Data {
        data.prefix(Int(Double(data.count) * fraction))
    }

    /// Random bytes, the same for the same seed on every run.
    private static func noise(count: Int, seed: UInt64) -> Data {
        var random = DemoRandomNumberGenerator(seed: seed)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count + 8)
        while bytes.count < count {
            withUnsafeBytes(of: random.next().littleEndian) { bytes.append(contentsOf: $0) }
        }
        return Data(bytes.prefix(count))
    }

    // MARK: PNG, by Hand

    private struct Chunk {
        let type: String
        var payload: Data
    }

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// A PNG of the given size in one color: an indexed image with a palette
    /// of one entry, one bit a pixel, and a row of zeros repeated, which
    /// compresses about a thousand to one.
    ///
    /// Indexed rather than grayscale because Nuke decompresses an image in its
    /// own color space where it can: a gray canvas would come out one byte a
    /// pixel, an indexed one comes out as RGB, four bytes a pixel, the way a
    /// photo does. Image I/O writes the same image at four times the size.
    /// Written here, the rows are compressed one at a time, so the 50 MB of
    /// them never exist at once.
    private static func flatPNG(width: Int, height: Int) -> Data? {
        let row = [UInt8](repeating: 0, count: 1 + (width + 7) / 8) // A filter byte, then the pixels
        guard let compressed = deflate(repeating: row, count: height) else {
            return nil
        }
        // A zlib stream: a header, the deflate data, and the Adler-32 of the
        // uncompressed bytes. For zeros only, that is 1, plus the byte count
        // in the upper half.
        let byteCount = UInt32((row.count * height) % 65521)
        let zlib = Data([0x78, 0x01]) + compressed + bigEndian(byteCount << 16 | 1)
        return png([
            header(width: width, height: height, bitDepth: 1, colorType: 3),
            Chunk(type: "PLTE", payload: Data([0x2F, 0x80, 0xED])),
            Chunk(type: "IDAT", payload: zlib),
            Chunk(type: "IEND", payload: Data())
        ])
    }

    /// Raw DEFLATE of `row` repeated `count` times, streamed.
    private static func deflate(repeating row: [UInt8], count: Int) -> Data? {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            return nil
        }
        defer { compression_stream_destroy(stream) }
        let bufferSize = 1 << 16
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        var output = Data()
        return row.withUnsafeBufferPointer { row -> Data? in
            for index in 0..<count {
                let isLast = index == count - 1
                stream.pointee.src_ptr = row.baseAddress!
                stream.pointee.src_size = row.count
                var status: compression_status
                repeat {
                    stream.pointee.dst_ptr = buffer
                    stream.pointee.dst_size = bufferSize
                    status = compression_stream_process(stream, isLast ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                    guard status != COMPRESSION_STATUS_ERROR else {
                        return nil
                    }
                    output.append(buffer, count: bufferSize - stream.pointee.dst_size)
                } while stream.pointee.src_size > 0 || (isLast && status == COMPRESSION_STATUS_OK)
            }
            return output
        }
    }

    private static func header(width: Int, height: Int, bitDepth: UInt8, colorType: UInt8) -> Chunk {
        // Compression, filter, and interlace methods: 0, the only ones there are.
        Chunk(type: "IHDR", payload: bigEndian(UInt32(width)) + bigEndian(UInt32(height)) + Data([bitDepth, colorType, 0, 0, 0]))
    }

    /// The chunks of a PNG, or `nil` for data that isn't one.
    private static func pngChunks(_ data: Data) -> [Chunk]? {
        let bytes = [UInt8](data)
        guard bytes.starts(with: pngSignature) else {
            return nil
        }
        var chunks: [Chunk] = []
        var offset = pngSignature.count
        while offset + 12 <= bytes.count {
            let length = bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            let start = offset + 8
            guard start + length + 4 <= bytes.count else {
                return nil
            }
            let type = String(decoding: bytes[offset + 4..<start], as: UTF8.self)
            chunks.append(Chunk(type: type, payload: Data(bytes[start..<start + length])))
            offset = start + length + 4
        }
        return chunks
    }

    /// A PNG of the chunks, each with its checksum worked out again.
    private static func png(_ chunks: [Chunk]) -> Data {
        var data = Data(pngSignature)
        for chunk in chunks {
            let body = Data(chunk.type.utf8) + chunk.payload
            data += bigEndian(UInt32(chunk.payload.count))
            data += body
            data += bigEndian(crc32(body))
        }
        return data
    }

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = crc & 1 != 0 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1
        }
        return crc
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    // MARK: Not Images

    private static let errorPage = """
        <!DOCTYPE html>
        <html>
        <head><title>404 Not Found</title></head>
        <body>
        <h1>Not Found</h1>
        <p>The requested URL was not found on this server.</p>
        </body>
        </html>

        """

    private static let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="160" height="120" viewBox="0 0 160 120">
          <rect width="160" height="120" fill="#2f80ed"/>
          <circle cx="80" cy="60" r="40" fill="#ffffff"/>
        </svg>

        """

    /// A one-page PDF with a red square, written out with the byte offsets
    /// its cross-reference table needs. Core Graphics would stamp a creation
    /// date in it, which changes the bytes on every run.
    private static var pdf: Data {
        let content = "1 0 0 rg 40 20 80 80 re f\n"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 160 120] /Contents 4 0 R >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream"
        ]
        var text = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let table = text.utf8.count
        text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            text += String(format: "%010d 00000 n \n", offset)
        }
        text += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(table)\n%%EOF\n"
        return Data(text.utf8)
    }

    // MARK: Bundle

    private static func bundled(_ name: String, _ ext: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw DemoFixtureError.missingResource("\(name).\(ext)")
        }
        return try Data(contentsOf: url)
    }
}
