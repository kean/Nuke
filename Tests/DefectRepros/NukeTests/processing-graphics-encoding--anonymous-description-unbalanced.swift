// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG (cosmetic): `ImageProcessors.Anonymous.description` is missing its
// closing parenthesis.
//
// `"AnonymousProcessor(identifier: \(identifier)"` – every other processor's
// description is balanced ("Circle(border: nil)", "GaussianBlur(radius: 8)",
// "Composition(processors: [...])"), and the descriptions are what
// `ImagePipeline.Error.processingFailed` and `Composition.description` print.
// Unlike an identifier, the description isn't part of a cache key, so it can
// be fixed without invalidating anything.
//
// Expected: "AnonymousProcessor(identifier: sepia)"
// Actual:   "AnonymousProcessor(identifier: sepia"
//
// Sources/Nuke/Processing/ImageProcessors+Anonymous.swift:29
@Suite(.timeLimit(.minutes(5)))
struct AnonymousDescriptionBugRepro {
    @Test func descriptionIsBalanced() {
        let processor = ImageProcessors.Anonymous(id: "sepia") { $0 }

        #expect(processor.description == "AnonymousProcessor(identifier: sepia)")
        #expect(
            ImageProcessors.Composition([processor]).description ==
            "Composition(processors: [AnonymousProcessor(identifier: sepia)])"
        )
    }
}
