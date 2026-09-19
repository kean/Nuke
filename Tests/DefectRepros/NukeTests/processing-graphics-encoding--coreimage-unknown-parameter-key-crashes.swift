// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: `ImageProcessors.CoreImageFilter(name:parameters:identifier:)` with a
// parameter key the filter doesn't have terminates the process.
//
// `applyFilter(named:parameters:to:)` passes the parameters straight to
// `CIFilter(name:parameters:)`, which sets each one with `setValue(_:forKey:)`.
// For an unknown key that raises an Objective-C `NSUnknownKeyException`
// ("[<CISepiaTone …> setValue:forUndefinedKey:]: this class is not key value
// coding-compliant for the key notAKey"), which Swift can't catch – the app
// crashes on the processing queue.
//
// Expected: the processor fails like it does for an unknown filter name –
// `ImageProcessors.CoreImageFilter.Error.failedToCreateFilter(name:parameters:)`,
// documented as "Failed to create a `CIFilter` with the given name and
// parameters" – and the request fails with `processingFailed`.
// Actual: the test process is killed ("Terminating app due to uncaught
// exception 'NSUnknownKeyException'"). A typo in a key, or a key that only
// exists on newer OS versions, is enough to crash an app in production.
// A fix could validate the keys against `filter.inputKeys` before setting them.
//
// NOTE: this repro crashes the test runner instead of recording a failure.
//
// Sources/Nuke/Processing/ImageProcessors+CoreImage.swift:104
@Suite(.timeLimit(.minutes(5)))
struct CoreImageFilterUnknownParameterBugRepro {
    @Test func unknownParameterKeyFailsTheProcessing() {
        // GIVEN a filter parameter with a misspelled key
        let processor = ImageProcessors.CoreImageFilter(
            name: "CISepiaTone",
            parameters: ["inputIntensty": 0.5],
            identifier: "sepia-50"
        )

        // THEN the processing fails instead of crashing
        #expect(throws: ImageProcessors.CoreImageFilter.Error.self) {
            try processor.process(ImageContainer(image: Test.image), context: .mock)
        }
    }
}
