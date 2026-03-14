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

@Suite struct ImageProcessingOptionsTests {

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
}
