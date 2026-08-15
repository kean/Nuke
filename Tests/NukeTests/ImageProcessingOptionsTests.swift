// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

@Suite(.timeLimit(.minutes(5)))
struct ImageProcessingOptionsTests {

    // MARK: - Unit

    @Test func unitPointsDescription() {
        let unit = ImageProcessingOptions.Unit.points
        #expect(unit.description == "points")
    }

    @Test func unitPixelsDescription() {
        let unit = ImageProcessingOptions.Unit.pixels
        #expect(unit.description == "pixels")
    }

    // MARK: - ContentMode

    @Test func contentModeAspectFillDescription() {
        let mode = ImageProcessingOptions.ContentMode.aspectFill
        #expect(mode.description == ".aspectFill")
    }

    @Test func contentModeAspectFitDescription() {
        let mode = ImageProcessingOptions.ContentMode.aspectFit
        #expect(mode.description == ".aspectFit")
    }

    // MARK: - Border

    @Test func borderDescription() {
#if canImport(UIKit)
        let border = ImageProcessingOptions.Border(color: .red, width: 2, unit: .pixels)
#else
        let border = ImageProcessingOptions.Border(color: .red, width: 2, unit: .pixels)
#endif
        #expect(border.description.contains("Border"))
        #expect(border.description.contains("pixels"))
    }

    @Test func borderDefaultWidth() {
#if canImport(UIKit)
        let border = ImageProcessingOptions.Border(color: .blue)
#else
        let border = ImageProcessingOptions.Border(color: .blue)
#endif
        #expect(border.width > 0)
    }

    @Test func bordersWithSameColorAndWidthAreEqual() {
        let a = ImageProcessingOptions.Border(color: .red, width: 2, unit: .pixels)
        let b = ImageProcessingOptions.Border(color: .red, width: 2, unit: .pixels)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func bordersWithDifferentColorsAreNotEqual() {
        let a = ImageProcessingOptions.Border(color: .red, width: 2, unit: .pixels)
        let b = ImageProcessingOptions.Border(color: .blue, width: 2, unit: .pixels)
        #expect(a != b)
    }

    @Test func bordersWithDifferentWidthsAreNotEqual() {
        let a = ImageProcessingOptions.Border(color: .red, width: 2, unit: .pixels)
        let b = ImageProcessingOptions.Border(color: .red, width: 4, unit: .pixels)
        #expect(a != b)
    }

    @Test func borderDescriptionForColorOutsideRGBColorSpace() {
        let border = ImageProcessingOptions.Border(color: .black, width: 2, unit: .pixels)
        #expect(border.description == "Border(color: #000000, width: 2.0 pixels)")
    }

    // MARK: - Color.hex

    @Test func hexForColorInRGBColorSpace() {
        #expect(Color.red.hex == "#FF0000")
    }

    /// On macOS, `getRed(_:green:blue:alpha:)` raises an `NSInvalidArgumentException`
    /// for any color outside an RGB color space, and `.black`, `.white`, and the
    /// grays are all in a grayscale one.
    @Test func hexForColorOutsideRGBColorSpace() {
        #expect(Color.black.hex == "#000000")
        #expect(Color.white.hex == "#FFFFFF")
    }

    @Test func hexForColorWithAlpha() {
        #expect(Color.black.withAlphaComponent(0.5).hex == "#00000080")
    }

#if os(macOS)
    /// Catalog colors, e.g. `NSColor.labelColor`, are another color space that
    /// `getRed(_:green:blue:alpha:)` can't read. Their value depends on the
    /// current appearance, so only the format is verified.
    @Test func hexForCatalogColor() throws {
        let hex = try #require(Color.labelColor.hex)
        #expect(hex.hasPrefix("#"))
        #expect(hex.count == 7 || hex.count == 9)
    }
#endif

    /// The components of a P3 color converted to (extended) sRGB fall outside
    /// of `0...1`, which used to produce malformed hex, e.g. `"#1170000"`.
    @Test func hexForWideGamutColorIsWellFormed() throws {
        let hex = try #require(Color(displayP3Red: 1, green: 0, blue: 0, alpha: 1).hex)
        #expect(hex == "#FF0000")
    }

    @Test func hexForWideGamutColorWithNegativeComponentsIsWellFormed() throws {
        let hex = try #require(Color(displayP3Red: 0, green: 1, blue: 0, alpha: 1).hex)
        #expect(hex.count == 7)
        #expect(hex.dropFirst().filter(\.isHexDigit).count == 6)
    }

    /// Pattern colors have no sRGB representation. They used to report all-zero
    /// components, which made every one of them – and `.clear` – hex to
    /// `"#00000000"` and share an identifier.
    @Test func hexForPatternColorIsNil() {
        #expect(Color(patternImage: Test.image).hex == nil)
        #expect(Color.clear.hex == "#00000000")
    }

    @Test func borderDescriptionsForPatternColorsDoNotCollide() {
        let a = ImageProcessingOptions.Border(color: Color(patternImage: Test.image), width: 2, unit: .pixels)
        let b = ImageProcessingOptions.Border(color: Color(patternImage: Test.image(named: "fixture-tiny", extension: "jpeg")), width: 2, unit: .pixels)
        let clear = ImageProcessingOptions.Border(color: .clear, width: 2, unit: .pixels)

        #expect(a.description != b.description)
        #expect(a.description != clear.description)
    }

    // MARK: - ContentMode

    @Test func contentModeEquality() {
        #expect(ImageProcessingOptions.ContentMode.aspectFill == .aspectFill)
        #expect(ImageProcessingOptions.ContentMode.aspectFit == .aspectFit)
        #expect(ImageProcessingOptions.ContentMode.aspectFill != .aspectFit)
    }
}
