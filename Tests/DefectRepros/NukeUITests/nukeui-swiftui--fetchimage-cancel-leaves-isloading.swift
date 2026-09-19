// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

// BUG: `FetchImage.cancel()` (Sources/NukeUI/FetchImage.swift:224-234)
// cancels the task and, per its own comment, "guarantees that no more
// callbacks will be delivered" – but it never clears `isLoading`. The only
// place `isLoading` goes back to `false` is `handle(result:)`, which a
// cancelled load never reaches, so `isLoading` stays `true` forever (until
// the next `load` or `reset`).
//
// Expected: `isLoading` – "Returns `true` if the image is being loaded" – is
// `false` once the load is cancelled. A custom view that shows a spinner
// while `isLoading` (the use case `FetchImage` exists for) otherwise spins
// indefinitely after a cancel.
// Actual: `isLoading == true` after `cancel()`, for both the pipeline-based
// and the async/await-based `load`.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct FetchImageCancelIsLoadingBugRepro {
    @Test func cancelEndsLoadingForAPipelineLoad() async {
        let dataLoader = MockDataLoader()
        dataLoader.isSuspended = true
        let image = FetchImage()
        image.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        image.load(Test.request)
        #expect(image.isLoading)

        image.cancel()

        // Expected: false. Actual: true.
        #expect(!image.isLoading)
    }

    @Test func cancelEndsLoadingForAnAsyncLoad() async {
        let gate = AsyncGate()
        let started = TestExpectation()
        let image = FetchImage()

        image.load {
            started.fulfill()
            await gate.wait()
            return Test.response
        }
        await started.wait()
        #expect(image.isLoading)

        image.cancel()

        // Expected: false. Actual: true.
        #expect(!image.isLoading)
        gate.open()
    }
}
