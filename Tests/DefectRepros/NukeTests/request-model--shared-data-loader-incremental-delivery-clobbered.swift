// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: creating a pipeline silently reconfigures the `DataLoader` of
// every other pipeline that shares it.
//
// `ImagePipeline.init` (Sources/Nuke/Pipeline/ImagePipeline.swift:95) writes
// `(configuration.dataLoader as? DataLoader)?.prefersIncrementalDelivery =
// configuration.isProgressiveDecodingEnabled`. `DataLoader` is a class, and the
// configuration docs point out that its copies share their class-typed members,
// so the usual way of deriving a second pipeline – copy the configuration of
// the first one and change an option – shares the loader. The last pipeline
// created wins.
//
// Expected: a pipeline with `isProgressiveDecodingEnabled = true` keeps
// receiving partial response bodies, whatever other pipelines are created.
// Actual: creating a second pipeline from its configuration without
// progressive decoding sets `prefersIncrementalDelivery` back to `false` on
// the shared loader, so `URLSession` stops delivering the body in increments
// and the first pipeline, whose configuration still says progressive decoding
// is on, no longer produces progressive previews.
// (The reverse also happens: a progressive pipeline turns incremental delivery
// on for a non-progressive one sharing its loader, or for a loader the app
// configured by hand.)
@Suite(.timeLimit(.minutes(1)))
struct RequestModelBugSharedDataLoaderTests {
    @Test func secondPipelineDoesNotDisableIncrementalDeliveryOfFirst() {
        // Given a progressive pipeline
        let dataLoader = DataLoader()
        let progressive = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
        }
        #expect(dataLoader.prefersIncrementalDelivery == true)

        // When another pipeline is derived from its configuration
        var configuration = progressive.configuration
        configuration.isProgressiveDecodingEnabled = false
        _ = ImagePipeline(configuration: configuration)

        // Then the first pipeline still gets partial response bodies
        #expect(progressive.configuration.isProgressiveDecodingEnabled == true)
        #expect(dataLoader.prefersIncrementalDelivery == true)
    }
}
