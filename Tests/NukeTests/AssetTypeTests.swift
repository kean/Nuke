// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct AssetTypeTests {
    // MARK: PNG

    @Test func detectPNG() {
        let data = Test.data(name: "fixture", extension: "png")
        #expect(AssetType(data[0..<1]) == nil)
        #expect(AssetType(data[0..<7]) == nil)
        #expect(AssetType(data[0..<8]) == .png)
        #expect(AssetType(data) == .png)
    }

    // MARK: GIF

    @Test func detectGIF() {
        let data = Test.data(name: "cat", extension: "gif")
        #expect(AssetType(data[0..<1]) == nil)
        #expect(AssetType(data[0..<5]) == nil)
        #expect(AssetType(data[0..<6]) == .gif)
        #expect(AssetType(data) == .gif)
    }

    @Test(arguments: ["GIF87a", "GIF89a"])
    func detectGIFVersions(signature: String) {
        let data = Data(signature.utf8) + Data([0x01, 0x00, 0x01, 0x00])
        #expect(AssetType(data) == .gif)
    }

    @Test func doesNotDetectGIFWithUnknownVersion() {
        // The version is part of the signature: anything else is not a GIF and
        // must not be given the type that makes the pipeline retain the data.
        #expect(AssetType(Data("GIF88a".utf8)) == nil)
        #expect(AssetType(Data("GIF".utf8) + Data([0x00, 0x00, 0x00])) == nil)
    }

    // MARK: JPEG

    @Test func detectBaselineJPEG() {
        let data = Test.data(name: "baseline", extension: "jpeg")
        #expect(AssetType(data[0..<1]) == nil)
        #expect(AssetType(data[0..<2]) == nil)
        #expect(AssetType(data[0..<3]) == .jpeg)
        #expect(AssetType(data) == .jpeg)
    }

    @Test func detectProgressiveJPEG() {
        let data = Test.data(name: "progressive", extension: "jpeg")
        // Not enough data
        #expect(AssetType(Data()) == nil)
        #expect(AssetType(data[0..<2]) == nil)

        // Enough to determine image format
        #expect(AssetType(data[0..<3]) == .jpeg)
        #expect(AssetType(data[0..<33]) == .jpeg)

        // Full image
        #expect(AssetType(data) == .jpeg)
    }

    // MARK: ICO

    @Test func detectICO() {
        let data = Test.data(name: "fixture", extension: "ico")
        #expect(AssetType(data[0..<1]) == nil)
        #expect(AssetType(data[0..<3]) == nil)
        #expect(AssetType(data[0..<4]) == .ico)
        #expect(AssetType(data) == .ico)
    }

    // MARK: BMP

    @Test func detectBMP() {
        let data = Data([0x42, 0x4D, 0x8A, 0x10])
        #expect(AssetType(data[0..<1]) == nil)
        #expect(AssetType(data[0..<2]) == .bmp)
        #expect(AssetType(data) == .bmp)
    }

    // MARK: TIFF

    @Test func detectLittleEndianTIFF() {
        let data = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
        #expect(AssetType(data[0..<3]) == nil)
        #expect(AssetType(data[0..<4]) == .tiff)
        #expect(AssetType(data) == .tiff)
    }

    @Test func detectBigEndianTIFF() {
        let data = Data([0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08])
        #expect(AssetType(data[0..<3]) == nil)
        #expect(AssetType(data[0..<4]) == .tiff)
        #expect(AssetType(data) == .tiff)
    }

    // MARK: JPEG 2000

    @Test func detectJPEG2000() {
        // The JP2 signature box.
        let data = Data([0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, 0x87, 0x0A])
        #expect(AssetType(data[0..<4]) == nil)
        #expect(AssetType(data[0..<11]) == nil)
        #expect(AssetType(data) == .jpeg2000)
    }

    @Test func detectJPEG2000Codestream() {
        // A raw codestream starts with the SOC and SIZ markers.
        let data = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x2F])
        #expect(AssetType(data[0..<3]) == nil)
        #expect(AssetType(data[0..<4]) == .jpeg2000)
        #expect(AssetType(data) == .jpeg2000)
    }

    // MARK: JPEG XL

    @Test func detectJPEGXL() {
        // The container signature box.
        let data = Data([0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A])
        #expect(AssetType(data[0..<4]) == nil)
        #expect(AssetType(data[0..<11]) == nil)
        #expect(AssetType(data) == .jxl)
    }

    @Test func detectJPEGXLCodestream() {
        // A naked codestream starts with the two-byte signature.
        let data = Data([0xFF, 0x0A, 0x00, 0x50])
        #expect(AssetType(data[0..<1]) == nil)
        #expect(AssetType(data[0..<2]) == .jxl)
        #expect(AssetType(data) == .jxl)
    }

    // MARK: WebP

    @Test func detectBaselineWebP() {
        let data = Test.data(name: "baseline", extension: "webp")
        #expect(AssetType(data[0..<1]) == nil)
        #expect(AssetType(data[0..<2]) == nil)
        #expect(AssetType(data[0..<12]) == .webp)
        #expect(AssetType(data) == .webp)
    }

    // MARK: HEIC

    @Test func detectHEIC() {
        let data = Test.data(name: "img_751", extension: "heic")
        // HEIC detection requires the ftyp box at byte offset 4 (8 bytes),
        // so 12 bytes total are needed. Shorter slices must return nil.
        #expect(AssetType(data[0..<1]) == nil)
        #expect(AssetType(data[0..<11]) == nil) // one byte short of the required 12
        // Exactly 12 bytes — enough to identify HEIC
        #expect(AssetType(data[0..<12]) == .heic)
        // Full data
        #expect(AssetType(data) == .heic)
    }

    // MARK: Video

    /// The first 16 bytes of an ISO base media file (MP4, M4V, MOV, HEIC): a
    /// box length, the `ftyp` box type, the four-character major brand, and a
    /// minor version.
    private func makeISOBaseMedia(brand: String, compatibleBrands: [String] = []) -> Data {
        let size = UInt8(16 + compatibleBrands.count * 4)
        return Data([0x00, 0x00, 0x00, size]) + Data("ftyp".utf8) + Data(brand.utf8) +
            Data(repeating: 0x00, count: 4) + compatibleBrands.flatMap { Data($0.utf8) }
    }

    @Test func detectMP4() {
        let data = makeISOBaseMedia(brand: "isom")
        // The major brand ends at byte 12, so shorter slices must return nil.
        #expect(AssetType(data[0..<11]) == nil)
        #expect(AssetType(data[0..<12]) == .mp4)
        #expect(AssetType(data) == .mp4)
    }

    @Test(arguments: ["isom", "iso2", "iso4", "iso5", "iso6", "mp41", "mp42", "mmp4", "avc1", "dash"])
    func detectMP4Brands(brand: String) {
        #expect(AssetType(makeISOBaseMedia(brand: brand)) == .mp4)
    }

    @Test func detectM4V() {
        let data = makeISOBaseMedia(brand: "M4V ")
        #expect(AssetType(data[0..<11]) == nil)
        #expect(AssetType(data[0..<12]) == .m4v)
        #expect(AssetType(data) == .m4v)
    }

    @Test(arguments: ["M4V ", "M4VH", "M4VP"])
    func detectM4VBrands(brand: String) {
        #expect(AssetType(makeISOBaseMedia(brand: brand)) == .m4v)
    }

    @Test func detectMOV() {
        let data = makeISOBaseMedia(brand: "qt  ")
        #expect(AssetType(data[0..<11]) == nil)
        #expect(AssetType(data[0..<12]) == .mov)
        #expect(AssetType(data) == .mov)
    }

    @Test func detectMP4Fixture() {
        // The fixture has an `mp42` major brand, which is a standard MP4 brand:
        // the system reports the file as `public.mpeg-4`.
        let data = Test.data(name: "video", extension: "mp4")
        #expect(AssetType(data) == .mp4)
        #expect(AssetType(data)?.utType == .mpeg4Movie)
    }

    @Test(arguments: ["heic", "heix", "heim", "heis", "hevc", "hevx", "hevm", "hevs"])
    func detectHEICBrands(brand: String) {
        #expect(AssetType(makeISOBaseMedia(brand: brand)) == .heic)
    }

    // MARK: AVIF

    @Test func detectAVIF() {
        let data = makeISOBaseMedia(brand: "avif")
        #expect(AssetType(data[0..<11]) == nil)
        #expect(AssetType(data[0..<12]) == .avif)
        #expect(AssetType(data) == .avif)
    }

    @Test(arguments: ["avif", "avis"])
    func detectAVIFBrands(brand: String) {
        // `avis` is the brand an AVIF image sequence uses.
        #expect(AssetType(makeISOBaseMedia(brand: brand)) == .avif)
    }

    // MARK: Edge Cases

    @Test func detectEmptyData() {
        #expect(AssetType(Data()) == nil)
    }

    @Test func detectUnknownFormat() {
        // Random bytes that don't match any known format
        let data = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        #expect(AssetType(data) == nil)
    }

    @Test(arguments: ["mif1", "msf1", "M4A ", "3gp4"])
    func detectUnsupportedISOBaseMediaBrands(brand: String) {
        // Bare HEIF, MPEG-4 audio, and 3GPP aren't formats the decoders
        // support, so the brands they use are not recognized.
        #expect(AssetType(makeISOBaseMedia(brand: brand)) == nil)
    }

    @Test func detectFormatDeclaredAsACompatibleBrand() {
        // `msf1` says the file is an image sequence and nothing about what its
        // frames are coded with, so the codec is left to the brands that
        // follow – which is exactly what Image I/O writes for a HEIC sequence.
        #expect(AssetType(makeISOBaseMedia(brand: "msf1", compatibleBrands: ["mif1", "heic", "hevc"])) == .heic)
        #expect(AssetType(makeISOBaseMedia(brand: "msf1", compatibleBrands: ["avis", "av01"])) == .avif)
        #expect(AssetType(makeISOBaseMedia(brand: "msf1", compatibleBrands: ["mif1", "MiPr"])) == nil)
    }

    // MARK: utType

    @Test func utTypeForBuiltInTypes() {
        #expect(AssetType.png.utType == .png)
        #expect(AssetType.jpeg.utType == .jpeg)
        #expect(AssetType.gif.utType == .gif)
        #expect(AssetType.heic.utType == .heic)
        #expect(AssetType.ico.utType == .ico)
        #expect(AssetType.bmp.utType == .bmp)
        #expect(AssetType.tiff.utType == .tiff)
        #expect(AssetType.jpeg2000.utType == UTType("public.jpeg-2000"))
        #expect(AssetType.jxl.utType == UTType("public.jpeg-xl"))
        #expect(AssetType.avif.utType == UTType("public.avif"))
        #expect(AssetType.webp.utType == .webP)
        #expect(AssetType.mp4.utType == .mpeg4Movie)
        #expect(AssetType.m4v.utType == UTType("com.apple.m4v-video"))
        #expect(AssetType.mov.utType == .quickTimeMovie)
    }

    @Test func builtInTypesUseTheIdentifiersTheSystemDeclares() {
        // A type the system doesn't declare can't be bridged, so every built-in
        // type has to use the identifier the system registers for the format.
        let types: [AssetType] = [.png, .jpeg, .gif, .heic, .ico, .bmp, .tiff, .jpeg2000, .jxl, .avif, .webp, .mp4, .m4v, .mov]
        for type in types {
            #expect(type.utType?.identifier == type.rawValue)
        }
    }

    @Test func utTypeForCustomType() {
        // A custom type that no bundle declares has no system counterpart.
        let type = AssetType(rawValue: "com.github.kean.nuke.not-a-real-type")
        #expect(type.utType == nil)
    }

    @Test func utTypeMetadata() {
        #expect(AssetType.png.utType?.preferredMIMEType == "image/png")
        #expect(AssetType.jpeg.utType?.preferredFilenameExtension == "jpeg")
        #expect(AssetType.webp.utType?.preferredMIMEType == "image/webp")
        #expect(AssetType.gif.utType?.conforms(to: .image) == true)
        #expect(AssetType.heic.utType?.conforms(to: .movie) == false)
    }

    @Test func utTypeConformanceIdentifiesVideo() {
        for type in [AssetType.mp4, .m4v, .mov] {
            #expect(type.utType?.conforms(to: .movie) == true)
        }
        for type in [AssetType.png, .jpeg, .gif, .heic, .ico, .bmp, .tiff, .jpeg2000, .jxl, .avif, .webp] {
            #expect(type.utType?.conforms(to: .image) == true)
            #expect(type.utType?.conforms(to: .movie) == false)
        }
    }

    // MARK: init(UTType)

    @Test func initWithUTType() {
        #expect(AssetType(UTType.png) == .png)
        #expect(AssetType(UTType.jpeg) == .jpeg)
        #expect(AssetType(UTType.gif) == .gif)
        #expect(AssetType(UTType.heic) == .heic)
        #expect(AssetType(UTType.ico) == .ico)
        #expect(AssetType(UTType.bmp) == .bmp)
        #expect(AssetType(UTType.tiff) == .tiff)
        #expect(AssetType(UTType.webP) == .webp)
        #expect(AssetType(UTType.mpeg4Movie) == .mp4)
        #expect(AssetType(UTType.quickTimeMovie) == .mov)
    }

    @Test func initWithUTTypeOutsideOfTheBuiltInTypes() {
        #expect(AssetType(UTType.pdf).rawValue == "com.adobe.pdf")
        #expect(AssetType(UTType.svg).rawValue == "public.svg-image")
        #expect(AssetType(UTType.icns).rawValue == "com.apple.icns")
    }

    @Test func roundTrip() {
        let types: [UTType] = [.png, .jpeg, .gif, .heic, .ico, .tiff, .bmp, .webP, .mpeg4Movie, .quickTimeMovie]
        for type in types {
            #expect(AssetType(type).utType == type)
        }
    }

    // MARK: Integration

    @Test func utTypeOfDecodedImage() throws {
        let data = Test.data(name: "fixture", extension: "png")
        let container = try ImageDecoders.Default().decode(data)
        #expect(container.type?.utType == .png)
    }

    /// Re-encodes the PNG fixture with Image I/O to check the sniffing against
    /// the headers the system itself writes, and to make sure the decoder
    /// reports a type for every format it decodes. There is no JPEG XL encoder,
    /// so that format is covered by the unit tests only.
    @Test(arguments: [AssetType.png, .jpeg, .gif, .heic, .bmp, .tiff, .jpeg2000, .avif])
    func detectDataProducedByImageIO(type: AssetType) throws {
        guard let data = encode(Test.data(name: "fixture", extension: "png"), as: type) else {
            return // The platform has no encoder for this format
        }
        #expect(AssetType(data) == type)

        let container = try ImageDecoders.Default().decode(data)
        #expect(container.type == type)
    }

    /// Re-encodes the given image data as the given type, or returns `nil` if
    /// the platform has no encoder for it.
    private func encode(_ data: Data, as type: AssetType) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.rawValue as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }
}
