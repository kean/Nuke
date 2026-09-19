// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import SwiftUI
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

// BUG (docs vs behavior): `LazyImage.processors(_:)` is documented as
//
//     /// Processors are only applied if the request does not already define its
//     /// own processors. The request's processors always take priority.
//
// (Sources/NukeUI/LazyImage.swift:101-104, reworded in cc581e83 "Update
// documentation"; before that it said "your processors will be applied
// instead"). The implementation on the next line still overwrites them
// unconditionally: `map { $0.context?.request.processors = processors ?? [] }`.
//
// Expected (per the doc, and per `FetchImage.processors`, which really does
// defer to the request): the request's processors are applied.
// Actual: the modifier's processors replace them. The existing
// `LazyImageTests.nilProcessorsClearRequestProcessors` pins the overwrite, so
// one of the two – the doc or the implementation – is wrong.
@Suite(.serialized, .timeLimit(.minutes(5))) @MainActor
struct LazyImageProcessorsDocumentationBugRepro {
    @Test func requestProcessorsTakePriorityOverTheModifier() async throws {
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        let completed = TestExpectation()
        let response = Ref<ImageResponse?>(nil)
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "request")])
        let host = ViewHost(request) { request in
            LazyImage(request: request)
                .pipeline(pipeline)
                .processors([MockImageProcessor(id: "modifier")])
                .onCompletion {
                    response.value = $0.value
                    completed.fulfill()
                }
        }
        await completed.wait()

        // Expected: ["request"]. Actual: ["modifier"].
        #expect(try #require(response.value).image.nk_test_processorIDs == ["request"])
        withExtendedLifetime(host) {}
    }
}

#endif
