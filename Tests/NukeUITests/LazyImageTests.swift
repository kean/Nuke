// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import SwiftUI
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

@Suite(.serialized, .timeLimit(.minutes(5))) @MainActor
struct LazyImageTests {
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
            $0.dataCache = MockDataCache()
        }
    }

    @Test func newRequestStartedWhenThumbnailChanges() async throws {
        let starts = Ref(0)
        let results = Ref<[Result<ImageResponse, Error>]>([])
        let first = TestExpectation()
        let second = TestExpectation()

        let host = ViewHost(Float(16)) { maxPixelSize in
            var request = ImageRequest(url: Test.url)
            request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: maxPixelSize)
            return LazyImage(request: request)
                .pipeline(pipeline)
                .onStart { _ in starts.value += 1 }
                .onCompletion {
                    results.value.append($0)
                    if results.value.count == 1 { first.fulfill() } else { second.fulfill() }
                }
        }
        await first.wait()
        let small = try #require(results.value.first).get()
        #expect(max(small.image.sizeInPixels.width, small.image.sizeInPixels.height) == 16)

        await host.update(64, until: { starts.value == 2 })
        #expect(starts.value == 2)
        guard starts.value == 2 else { return }
        await second.wait()

        let large = try #require(results.value.last).get()
        #expect(max(large.image.sizeInPixels.width, large.image.sizeInPixels.height) == 64)
    }

    @Test func newRequestStartedWhenScaleChanges() async throws {
        let starts = Ref(0)
        let results = Ref<[Result<ImageResponse, Error>]>([])
        let first = TestExpectation()
        let second = TestExpectation()

        let host = ViewHost(Float(1)) { scale in
            var request = ImageRequest(url: Test.url)
            request.scale = scale
            return LazyImage(request: request)
                .pipeline(pipeline)
                .onStart { _ in starts.value += 1 }
                .onCompletion {
                    results.value.append($0)
                    if results.value.count == 1 { first.fulfill() } else { second.fulfill() }
                }
        }
        await first.wait()

        await host.update(2, until: { starts.value == 2 })
        #expect(starts.value == 2)
        guard starts.value == 2 else { return }
        await second.wait()

        #expect(try #require(results.value.last).get().request.scale == 2)
    }
}

#endif
