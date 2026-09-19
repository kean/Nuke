// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: `ImageRequest.scale` doesn't return the value it was set to.
//
// Nuke 14 changed the public type of `ImageRequest.scale` from `Float` to
// `CGFloat` "matching the types you get from UIKit and SwiftUI" (migration
// guide, CHANGELOG #910), but the storage stayed `Float`
// (Sources/Nuke/ImageRequest.swift:114 `$0.scale = Float(newValue)`, and
// `Container.scale: Float` at :516), so every value that isn't exactly
// representable as a `Float` is silently rounded.
//
// Expected: `request.scale = 2.608; request.scale == 2.608` (2.608 is the
// `nativeScale` of the Plus-size iPhones; 2.88 and 3.0 are other real ones).
// Actual: `request.scale == 2.6080000400543213`, and the decoded image gets
// that scale too (`ImageDecoders.Default` reads `context.request.scale`), so
// `image.scale != screen.nativeScale` and the point size is off by ~1e-8.
@Suite(.timeLimit(.minutes(1)))
struct RequestModelBugScaleRoundTripTests {
    @Test(arguments: [2.608, 2.88, 1.1] as [CGFloat])
    func scaleIsReadBackAsSet(_ scale: CGFloat) {
        // When
        var request = ImageRequest(url: Test.url)
        request.scale = scale

        // Then
        #expect(request.scale == scale)
    }
}
