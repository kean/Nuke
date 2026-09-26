// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import ImageIO
@testable import Nuke

/// The edges of the header sniffing in ``AssetType``: the shortest inputs, the
/// data slices that don't start at zero, the container fields that lie, and
/// the formats Image I/O decodes but the sniffer deliberately doesn't name.
@Suite(.timeLimit(.minutes(5)))
struct AssetTypeSniffingBoundaryTests {

    // MARK: Short Inputs

    @Test func noSingleByteIsAnImage() {
        for byte in UInt8.min...UInt8.max {
            #expect(AssetType(Data([byte])) == nil)
        }
    }

    @Test func onlyTheTwoByteSignaturesMatchTwoBytes() {
        // BMP and the JPEG XL codestream are the only formats identified by
        // two bytes; any other match on two bytes reads past the end of the
        // data or matches a signature by a prefix.
        var matches: [[UInt8]: AssetType] = [:]
        for first in UInt8.min...UInt8.max {
            for second in UInt8.min...UInt8.max {
                if let type = AssetType(Data([first, second])) {
                    matches[[first, second]] = type
                }
            }
        }
        #expect(matches == [[0x42, 0x4D]: .bmp, [0xFF, 0x0A]: .jxl])
    }

    // MARK: Slices

    /// The pipeline accumulates the downloaded data, and a caller can hand in
    /// any slice of a larger buffer: every read has to be relative to the
    /// slice's own start index, not to zero.
    @Test(arguments: [
        ("fixture", "png", AssetType.png),
        ("baseline", "jpeg", .jpeg),
        ("cat", "gif", .gif),
        ("baseline", "webp", .webp),
        ("img_751", "heic", .heic),
        ("animated", "avif", .avif),
        ("fixture", "ico", .ico)
    ])
    func sniffsASliceThatDoesNotStartAtZero(name: String, ext: String, type: AssetType) {
        // The bytes in front spell the BMP signature, so a read from index
        // zero would be caught answering `.bmp`.
        let data = Test.data(name: name, extension: ext)
        let slice = (Data([0x42, 0x4D, 0x00, 0x00, 0x00, 0x00, 0x00]) + data)[7...]
        #expect(slice.startIndex == 7)

        #expect(AssetType(slice) == type)
    }

    @Test func detectsAnimationInASliceThatDoesNotStartAtZero() throws {
        func slice(_ data: Data) -> Data {
            (Data(repeating: 0x00, count: 13) + data)[13...]
        }
        let apng = try #require(Test.animatedPNG())

        #expect(AssetType.isAnimated(slice(apng), type: .png))
        #expect(AssetType.isAnimated(slice(Test.data(name: "animated", extension: "webp")), type: .webp))
        #expect(AssetType.isAnimated(slice(Test.data(name: "animated", extension: "avif")), type: .avif))
        #expect(AssetType.isAnimated(slice(Test.staticPNG()), type: .png) == false)
        #expect(AssetType.isAnimated(slice(Test.data(name: "baseline", extension: "webp")), type: .webp) == false)
    }

    // MARK: ISO Base Media

    @Test func brandsPastTheEndOfTheFileTypeBoxAreIgnored() {
        // The bytes that follow the `ftyp` box belong to the next box. Read as
        // brands, the size of a box that happens to spell `heic` would turn a
        // file with no known brand into a HEIC.
        var data = makeFileTypeBox(declaredSize: 16, brands: ["msf1"])
        data += Data("heic".utf8) + Data("meta".utf8)

        #expect(AssetType(data) == nil)
        #expect(AssetType(makeFileTypeBox(brands: ["msf1", "heic"])) == .heic)
    }

    @Test func fileTypeBoxLargerThanTheDataReadsTheBrandsThatArePresent() {
        // A box size that says more than was downloaded – or a damaged one –
        // must neither trap nor read past the end.
        let data = makeFileTypeBox(declaredSize: 0xFFFF_FFFF, brands: ["msf1", "mif1", "heic"])

        #expect(AssetType(data) == .heic)
        #expect(AssetType.isAnimated(data, type: .heic))
    }

    @Test func fileTypeBoxSizeDoesNotMakeTheSniffWalkTheFile() {
        // A declared size of 0xFFFFFFFF and no known brand. Read to the end of
        // the data, the sniff is O(file size) – seconds for this file in a
        // Debug build – and it runs on the pipeline's actor, for every decode.
        var data = makeFileTypeBox(declaredSize: 0xFFFF_FFFF, brands: ["zzzz"])
        data += Data(repeating: 0x41, count: 32_000_000)

        let clock = ContinuousClock()
        var type: AssetType?
        let elapsed = clock.measure {
            type = AssetType(data)
        }

        #expect(type == nil)
        #expect(elapsed < .milliseconds(100))
    }

    @Test func brandFarPastAnyRealFileTypeBoxIsNotRead() {
        var data = makeFileTypeBox(declaredSize: 0xFFFF_FFFF, brands: ["zzzz"])
        data += Data(repeating: 0x41, count: 1_000_000)
        data += Data("hevc".utf8)

        #expect(AssetType(data) == nil)
        #expect(AssetType.isAnimated(data, type: .heic) == false)
    }

    @Test func fileTypeBoxIsReadUpToSixtyCompatibleBrands() {
        // A real `ftyp` box lists a handful of compatible brands; sixty is
        // where the sniff stops trusting the declared size.
        let filler = Array(repeating: "mif1", count: 59)
        #expect(AssetType(makeFileTypeBox(brands: ["msf1"] + filler + ["heic"])) == .heic)
        #expect(AssetType(makeFileTypeBox(brands: ["msf1"] + filler + ["mif1", "heic"])) == nil)
    }

    @Test func truncatedCompatibleBrandIsNotRead() {
        // Two of the four bytes of `heic`: not enough to name the codec yet.
        let data = makeFileTypeBox(brands: ["msf1", "mif1", "heic"]).prefix(22)

        #expect(AssetType(data) == nil)
    }

    @Test func fileTypeBoxWithADamagedSizeStillNamesItsMajorBrand() {
        // Documented in `_brands(in:)`: the major brand is read whatever the
        // declared size says – here, sizes too small to even hold it.
        for size: UInt32 in [0, 8, 11] {
            #expect(AssetType(makeFileTypeBox(declaredSize: size, brands: ["avif", "msf1"])) == .avif)
        }
    }

    // MARK: Near Misses

    @Test func cursorSniffsAsNothing() {
        // Documented: CUR is one byte away from the ICO signature.
        #expect(AssetType(Data([0x00, 0x00, 0x02, 0x00, 0x01, 0x00])) == nil)
        #expect(AssetType(Data([0x00, 0x00, 0x01, 0x00, 0x01, 0x00])) == .ico)
    }

    @Test func riffContainerThatIsNotWebPSniffsAsNothing() {
        // WAV and AVI share the RIFF wrapper.
        var data = Data("RIFF".utf8) + Data([0x24, 0x00, 0x00, 0x00])
        data += Data("WAVEfmt ".utf8)
        #expect(AssetType(data) == nil)
    }

    // MARK: Formats the Sniffer Doesn't Name

    /// Documented in "Supported Formats": when the sniffer doesn't recognize
    /// the data, the type is `nil` and the image still decodes – nothing in
    /// the pipeline gates on the type.
    @Test(arguments: ["com.apple.icns", "com.adobe.photoshop-image", "com.truevision.tga-image", "com.ilm.openexr-image", "public.pbm"])
    func formatTheSnifferDoesNotNameStillDecodes(identifier: String) throws {
        guard let data = encode(as: identifier) else {
            return // No encoder for this format on this platform
        }
        #expect(AssetType(data) == nil)

        let container = try ImageDecoders.Default().decode(data)

        #expect(container.type == nil)
        #expect(container.image.sizeInPixels == CGSize(width: 16, height: 16))
        // Not recognized, so not recognized as animated either
        #expect(container.data == nil)
        #expect(container.animation == nil)
    }

    // MARK: Animation Detection

    @Test func animatedWebPIsDetectedFromTheFlagsByte() {
        let data = makeWebP(chunk: "VP8X", flags: 0x02)
        // The flags are byte 20: 21 bytes are enough, 20 are not.
        #expect(AssetType.isAnimated(data.prefix(21), type: .webp))
        #expect(AssetType.isAnimated(data.prefix(20), type: .webp) == false)
    }

    @Test func onlyTheAnimationBitMarksAWebPAsAnimated() {
        #expect(AssetType.isAnimated(makeWebP(chunk: "VP8X", flags: 0xFF), type: .webp))
        #expect(AssetType.isAnimated(makeWebP(chunk: "VP8X", flags: 0xFD), type: .webp) == false)
    }

    @Test(arguments: ["VP8 ", "VP8L"])
    func simpleWebPIsNeverAnimated(chunk: String) {
        // The lossy and lossless formats have no feature flags: whatever sits
        // at byte 20 is image data, animation bit or not.
        #expect(AssetType.isAnimated(makeWebP(chunk: chunk, flags: 0xFF), type: .webp) == false)
    }

    @Test func apngControlChunkIsFoundPastALargeAncillaryChunk() {
        let data = makePNG(chunks: [
            ("IHDR", Data(count: 13)),
            ("iTXt", Data(repeating: 0x41, count: 5000)),
            ("acTL", Data(count: 8)),
            ("IDAT", Data(count: 4))
        ])
        #expect(AssetType(data) == .png)
        #expect(AssetType.isAnimated(data, type: .png))
    }

    @Test func apngControlChunkNameInsideAPayloadIsNotAChunk() {
        // The chunks are walked by their lengths, not searched for by name.
        let data = makePNG(chunks: [
            ("IHDR", Data(count: 13)),
            ("tEXt", Data("Comment\u{0}acTL".utf8)),
            ("IDAT", Data(count: 4))
        ])
        #expect(AssetType.isAnimated(data, type: .png) == false)
    }

    @Test func apngControlChunkAfterTheImageDataIsIgnored() {
        // The format requires `acTL` before the first `IDAT`: one after it
        // doesn't make the file an animation, so the walk stops at the pixels.
        let data = makePNG(chunks: [
            ("IHDR", Data(count: 13)),
            ("IDAT", Data(count: 4)),
            ("acTL", Data(count: 8))
        ])
        #expect(AssetType.isAnimated(data, type: .png) == false)
    }

    @Test(arguments: [UInt32(Int32.max), UInt32(Int32.max) + 1])
    func pngChunkLengthAtTheLimitEndsTheWalk(length: UInt32) {
        var data = makePNG(chunks: [("IHDR", Data(count: 13))])
        data += bigEndian(length) + Data("tEXt".utf8) + Data(count: 16)
        data += makeChunk("acTL", Data(count: 8))

        #expect(AssetType.isAnimated(data, type: .png) == false)
    }

    @Test func animationDetectionTrustsTheTypeItIsGiven() {
        // Every GIF has its data attached, whatever the bytes say...
        #expect(AssetType.isAnimated(Test.data, type: .gif))
        // ...while the other formats read their own headers, and bytes that
        // aren't that format are not an animation of it.
        #expect(AssetType.isAnimated(Test.data, type: .heic) == false)
        #expect(AssetType.isAnimated(Test.data, type: .avif) == false)
        #expect(AssetType.isAnimated(Test.data, type: .webp) == false)
        #expect(AssetType.isAnimated(Test.data, type: .png) == false)
        #expect(AssetType.isAnimated(Test.data(name: "animated", extension: "webp"), type: .png) == false)
        #expect(AssetType.isAnimated(Test.data(name: "animated", extension: "avif"), type: .mp4) == false)
    }

    // MARK: Helpers

    private func makeFileTypeBox(declaredSize: UInt32? = nil, brands: [String]) -> Data {
        // The major brand, a minor version, then the compatible brands.
        var payload = Data(brands[0].utf8) + Data(count: 4)
        for brand in brands.dropFirst() {
            payload += Data(brand.utf8)
        }
        return bigEndian(declaredSize ?? UInt32(8 + payload.count)) + Data("ftyp".utf8) + payload
    }

    private func makeWebP(chunk: String, flags: UInt8) -> Data {
        var data = Data("RIFF".utf8) + Data([0x20, 0x00, 0x00, 0x00]) + Data("WEBP".utf8)
        data += Data(chunk.utf8) + Data([0x0A, 0x00, 0x00, 0x00])
        data += Data([flags]) + Data(count: 9)
        return data
    }

    private func makePNG(chunks: [(String, Data)]) -> Data {
        chunks.reduce(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) { $0 + makeChunk($1.0, $1.1) }
    }

    /// A length, a name, the payload, and a CRC the sniffer never checks.
    private func makeChunk(_ name: String, _ payload: Data) -> Data {
        bigEndian(UInt32(payload.count)) + Data(name.utf8) + payload + Data(count: 4)
    }

    private func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private func encode(as identifier: String) -> Data? {
        let context = CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let output = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(output, identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length > 0 else {
            return nil
        }
        return output as Data
    }
}
