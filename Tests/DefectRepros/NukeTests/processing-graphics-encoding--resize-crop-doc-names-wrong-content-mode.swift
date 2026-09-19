// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// DOCS BUG: the `crop` parameter of `ImageProcessors.Resize` is documented
// with the content modes swapped.
//
// - `ImageProcessors.Resize.init(size:unit:contentMode:crop:upscale:)`:
//   "crop: If `true`, crops the image to exactly match the target size. Has
//   no effect when `contentMode` is `.aspectFill`."
// - `ImageProcessing.resize(size:unit:contentMode:crop:upscale:)`:
//   "crop: If `true` will crop the image to match the target size. Does
//   nothing with content mode .aspectFill."
//
// The implementation – `if crop && contentMode == .aspectFill` – does the
// opposite, which is also the only mode where cropping means anything:
// `crop` works *only* with `.aspectFill` and has no effect with `.aspectFit`
// (`ImageProcessorsResizeTests.thatImageIsntCroppedWithAspectFitMode` pins
// that). The test below asserts what the docs say and fails; the fix belongs
// in the two doc comments, not in the code.
//
// Expected (per docs): `crop` changes nothing with `.aspectFill`.
// Actual: a 640x480 image is 400x400 with `crop: true` and 533x400 without.
//
// Sources/Nuke/Processing/ImageProcessors+Resize.swift:29 and
// Sources/Nuke/Processing/ImageProcessors.swift:25
@Suite(.timeLimit(.minutes(5)))
struct ResizeCropDocumentationBugRepro {
    @Test func cropHasNoEffectWithAspectFillAsDocumented() throws {
        // GIVEN
        let cropped = ImageProcessors.Resize(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFill, crop: true)
        let notCropped = ImageProcessors.Resize(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFill, crop: false)

        // WHEN
        let lhs = try #require(cropped.process(Test.image))
        let rhs = try #require(notCropped.process(Test.image))

        // THEN
        #expect(lhs.sizeInPixels == rhs.sizeInPixels) // Actual: (400, 400) vs (533, 400)
    }
}
