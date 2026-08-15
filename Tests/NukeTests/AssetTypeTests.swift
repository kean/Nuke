// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
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
        #expect(AssetType(data) == .gif)
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
    private func makeISOBaseMedia(brand: String) -> Data {
        Data([0x00, 0x00, 0x00, 0x20]) + Data("ftyp".utf8) + Data(brand.utf8) + Data(repeating: 0x00, count: 4)
    }

    @Test func detectMP4() {
        let data = makeISOBaseMedia(brand: "isom")
        // The major brand ends at byte 12, so shorter slices must return nil.
        #expect(AssetType(data[0..<11]) == nil)
        #expect(AssetType(data[0..<12]) == .mp4)
        #expect(AssetType(data) == .mp4)
    }

    @Test func detectM4V() {
        let data = makeISOBaseMedia(brand: "M4V ")
        #expect(AssetType(data[0..<11]) == nil)
        #expect(AssetType(data[0..<12]) == .m4v)
        #expect(AssetType(data) == .m4v)
    }

    @Test func detectMOV() {
        let data = makeISOBaseMedia(brand: "qt  ")
        #expect(AssetType(data[0..<11]) == nil)
        #expect(AssetType(data[0..<12]) == .mov)
        #expect(AssetType(data) == .mov)
    }

    @Test func detectMP4Fixture() {
        let data = Test.data(name: "video", extension: "mp4")
        // Known issue: the fixture has an `mp42` major brand, which the
        // detection maps to `.m4v`. `mp42` is a standard MP4 brand – the system
        // reports the file as `public.mpeg-4` – so this is a misclassification.
        // Update the expectation to `.mp4` when the `ftyp` brands are parsed.
        #expect(AssetType(data) == .m4v)
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

    @Test func detectUnknownISOBaseMediaBrand() {
        // `mif1` is the generic HEIF brand and isn't one of the brands the
        // detection matches.
        #expect(AssetType(makeISOBaseMedia(brand: "mif1")) == nil)
    }

    // MARK: utType

    @Test func utTypeForSystemDeclaredTypes() {
        #expect(AssetType.png.utType == .png)
        #expect(AssetType.jpeg.utType == .jpeg)
        #expect(AssetType.gif.utType == .gif)
        #expect(AssetType.heic.utType == .heic)
        #expect(AssetType.ico.utType == .ico)
    }

    @Test func utTypeForIdentifiersTheSystemDoesNotDeclare() {
        // These four identifiers aren't the ones the system uses for these
        // formats (`org.webmproject.webp`, `public.mpeg-4`,
        // `com.apple.m4v-video`, and `com.apple.quicktime-movie`), so they
        // can't be bridged.
        #expect(AssetType.webp.utType == nil)
        #expect(AssetType.mp4.utType == nil)
        #expect(AssetType.m4v.utType == nil)
        #expect(AssetType.mov.utType == nil)
    }

    @Test func utTypeForCustomType() {
        // A custom type that no bundle declares has no system counterpart.
        let type = AssetType(rawValue: "com.github.kean.nuke.not-a-real-type")
        #expect(type.utType == nil)
    }

    @Test func utTypeMetadata() {
        #expect(AssetType.png.utType?.preferredMIMEType == "image/png")
        #expect(AssetType.jpeg.utType?.preferredFilenameExtension == "jpeg")
        #expect(AssetType.gif.utType?.conforms(to: .image) == true)
        #expect(AssetType.heic.utType?.conforms(to: .movie) == false)
    }

    // MARK: init(UTType)

    @Test func initWithUTType() {
        #expect(AssetType(UTType.png) == .png)
        #expect(AssetType(UTType.jpeg) == .jpeg)
        #expect(AssetType(UTType.gif) == .gif)
        #expect(AssetType(UTType.heic) == .heic)
        #expect(AssetType(UTType.ico) == .ico)
    }

    @Test func initWithUTTypeOutsideOfTheBuiltInTypes() {
        #expect(AssetType(UTType.tiff).rawValue == "public.tiff")
        #expect(AssetType(UTType.webP).rawValue == "org.webmproject.webp")
        #expect(AssetType(UTType.mpeg4Movie).rawValue == "public.mpeg-4")
        #expect(AssetType(UTType.quickTimeMovie).rawValue == "com.apple.quicktime-movie")
    }

    @Test func initWithUTTypeDoesNotMatchTheBuiltInVideoTypes() {
        // The built-in video types use identifiers the system doesn't declare,
        // so bridging the system types back doesn't produce them.
        #expect(AssetType(UTType.mpeg4Movie) != .mp4)
        #expect(AssetType(UTType.quickTimeMovie) != .mov)
        #expect(AssetType(UTType.webP) != .webp)
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
}
