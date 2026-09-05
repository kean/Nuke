// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke

/// Covers `AssetType.isAnimated`, which decides whether the pipeline keeps the
/// encoded data around so that something can play the animation.
@Suite(.timeLimit(.minutes(5)))
struct AnimatedImageDetectionTests {
    // MARK: GIF

    @Test func detectsAnimatedGIF() {
        let data = Test.animatedGIF()
        #expect(AssetType.isAnimated(data, type: .gif))
    }

    @Test func treatsStillGIFAsAnimated() {
        // Long-standing behavior: the data of every GIF is attached, so that a
        // still one can be handed to a renderer as well.
        #expect(AssetType.isAnimated(Test.animatedGIF(frameCount: 1), type: .gif))
    }

    // MARK: PNG

    @Test func detectsAPNG() throws {
        let data = try #require(Test.animatedPNG())
        #expect(AssetType(data) == .png)
        #expect(AssetType.isAnimated(data, type: .png))
    }

    @Test func doesNotDetectStaticPNG() {
        let data = Test.staticPNG()
        #expect(AssetType(data) == .png)
        #expect(AssetType.isAnimated(data, type: .png) == false)
    }

    @Test func doesNotDetectPNGFixtureAsAnimated() {
        #expect(AssetType.isAnimated(Test.data(name: "fixture", extension: "png"), type: .png) == false)
    }

    @Test func handlesTruncatedPNG() {
        let data = Test.staticPNG()
        for count in [0, 1, 8, 12, 20] {
            #expect(AssetType.isAnimated(data.prefix(count), type: .png) == false)
        }
    }

    @Test func handlesPNGWithAbsurdChunkLength() {
        // A length that would overflow the offset must end the scan, not trap.
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // Length
        data.append(contentsOf: Array("tEXt".utf8))
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        #expect(AssetType.isAnimated(data, type: .png) == false)
    }

    // MARK: WebP

    @Test func detectsAnimatedWebP() {
        #expect(AssetType.isAnimated(makeWebP(flags: 0x02), type: .webp))
    }

    @Test func doesNotDetectStaticWebP() {
        #expect(AssetType.isAnimated(makeWebP(flags: 0x10), type: .webp) == false) // Alpha, not animation
        #expect(AssetType.isAnimated(Test.data(name: "baseline", extension: "webp"), type: .webp) == false)
    }

    @Test func handlesTruncatedWebP() {
        let data = makeWebP(flags: 0x02)
        for count in 0..<21 {
            #expect(AssetType.isAnimated(data.prefix(count), type: .webp) == false)
        }
    }

    // MARK: HEIC and AVIF

    @Test(arguments: ["hevc", "hevx", "hevm", "hevs", "msf1"])
    func detectsHEICSequenceBrands(brand: String) {
        #expect(AssetType.isAnimated(makeISOBaseMedia(majorBrand: brand), type: .heic))
    }

    @Test(arguments: ["heic", "heix", "heim", "heis"])
    func doesNotDetectStillHEICBrands(brand: String) {
        #expect(AssetType.isAnimated(makeISOBaseMedia(majorBrand: brand), type: .heic) == false)
    }

    @Test func detectsAVIFSequence() {
        #expect(AssetType.isAnimated(makeISOBaseMedia(majorBrand: "avis"), type: .avif))
        #expect(AssetType.isAnimated(makeISOBaseMedia(majorBrand: "avif"), type: .avif) == false)
    }

    @Test func detectsSequenceDeclaredAsACompatibleBrand() {
        // Encoders routinely put a still brand up front and declare the
        // sequence in the compatible brands that follow.
        let data = makeISOBaseMedia(majorBrand: "heic", compatibleBrands: ["mif1", "msf1"])
        #expect(AssetType.isAnimated(data, type: .heic))
    }

    @Test func detectsAnimatedHEICWrittenByImageIO() throws {
        // The brands a real sequence carries, not the ones a test picked:
        // Image I/O leads with `msf1`, which says the file holds a sequence
        // without saying what codec it uses, and names the codec further down
        // the compatible brands. Sniffing only the major brand answered `nil`
        // here, and an animation the pipeline can't type is one it never
        // attaches the data to.
        let data = try #require(Test.animatedHEICS())
        #expect(AssetType(data) == .heic)
        #expect(AssetType.isAnimated(data, type: AssetType(data)))
    }

    @Test func detectsAnimatedAVIFFixture() {
        let data = Test.data(name: "animated", extension: "avif")
        #expect(AssetType(data) == .avif)
        #expect(AssetType.isAnimated(data, type: .avif))
    }

    @Test func doesNotDetectStillHEICFixture() {
        let data = Test.data(name: "img_751", extension: "heic")
        #expect(AssetType(data) == .heic)
        #expect(AssetType.isAnimated(data, type: .heic) == false)
    }

    // MARK: Other Formats

    @Test func doesNotDetectFormatsThatCannotAnimate() {
        #expect(AssetType.isAnimated(Test.data, type: .jpeg) == false)
        #expect(AssetType.isAnimated(Test.data, type: nil) == false)
        #expect(AssetType.isAnimated(Data(), type: .png) == false)
    }

    // MARK: Helpers

    /// A WebP header: the RIFF wrapper, the `VP8X` chunk, and its feature flags.
    private func makeWebP(flags: UInt8) -> Data {
        var data = Data("RIFF".utf8)
        data.append(contentsOf: [0x20, 0x00, 0x00, 0x00])
        data.append(contentsOf: Array("WEBP".utf8))
        data.append(contentsOf: Array("VP8X".utf8))
        data.append(contentsOf: [0x0A, 0x00, 0x00, 0x00]) // Chunk size
        data.append(flags)
        data.append(contentsOf: [UInt8](repeating: 0, count: 9))
        return data
    }

    /// An ISO base media `ftyp` box with the given brands.
    private func makeISOBaseMedia(majorBrand: String, compatibleBrands: [String] = []) -> Data {
        let size = 16 + compatibleBrands.count * 4
        var data = Data([UInt8(size >> 24), UInt8((size >> 16) & 0xFF), UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF)])
        data.append(contentsOf: Array("ftyp".utf8))
        data.append(contentsOf: Array(majorBrand.utf8))
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Minor version
        for brand in compatibleBrands {
            data.append(contentsOf: Array(brand.utf8))
        }
        return data
    }
}
