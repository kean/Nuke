// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import SwiftUI
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

// BUG: `LazyImageContext.==` (Sources/NukeUI/LazyImage.swift:206-218)
// compares `imageID`, `priority`, `processors` and `options` only. It ignores
// `ImageRequest.thumbnail` and `ImageRequest.scale`, both of which are part of
// the memory cache key (`MemoryCacheKey`, Sources/Nuke/Internal/ImageRequestKeys.swift)
// and change the image the pipeline produces.
//
// Expected: a `LazyImage` whose request changes only its thumbnail options
// (e.g. a cell that grows from 16 px to 64 px) or its scale reloads, like it
// does when only the processors change (CHANGELOG: "Fix an issue where the
// image won't reload if you change only LazyImage processors or priority").
//
// Actual: the two contexts compare equal, `onChange(of: context)` never
// fires, no request starts, and the view keeps showing the 16 px thumbnail
// (or the image at the old scale) for the new request.
@Suite(.serialized, .timeLimit(.minutes(5))) @MainActor
struct LazyImageThumbnailAndScaleChangesBugRepro {
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
        }
    }

    @Test func changingTheThumbnailSizeReloads() async throws {
        let starts = Ref(0)
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let first = TestExpectation()
        let second = TestExpectation()
        let host = ViewHost(CGFloat(16)) { maxPixelSize in
            LazyImage(request: makeRequest(maxPixelSize: maxPixelSize))
                .pipeline(pipeline)
                .onStart { _ in starts.value += 1 }
                .onCompletion {
                    results.value.append($0)
                    if results.value.count == 1 { first.fulfill() } else { second.fulfill() }
                }
        }
        await first.wait()
        let small = try #require(results.value.first?.value)
        #expect(max(small.image.sizeInPixels.width, small.image.sizeInPixels.height) == 16)

        await host.update(64, until: { starts.value == 2 })

        // Expected: 2. Actual: 1 – the view never asks for the bigger thumbnail.
        #expect(starts.value == 2)
        guard starts.value == 2 else { return }
        await second.wait()
        let large = try #require(results.value.last?.value)
        #expect(max(large.image.sizeInPixels.width, large.image.sizeInPixels.height) == 64)
    }

    @Test func changingTheScaleReloads() async throws {
        let starts = Ref(0)
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let first = TestExpectation()
        let second = TestExpectation()
        let host = ViewHost(CGFloat(1)) { scale in
            LazyImage(request: makeRequest(scale: scale))
                .pipeline(pipeline)
                .onStart { _ in starts.value += 1 }
                .onCompletion {
                    results.value.append($0)
                    if results.value.count == 1 { first.fulfill() } else { second.fulfill() }
                }
        }
        await first.wait()

        await host.update(2, until: { starts.value == 2 })

        // Expected: 2. Actual: 1.
        #expect(starts.value == 2)
        guard starts.value == 2 else { return }
        await second.wait()
        #expect(try #require(results.value.last?.value).request.scale == 2)
    }

    private func makeRequest(maxPixelSize: CGFloat) -> ImageRequest {
        var request = ImageRequest(url: Test.url)
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: maxPixelSize)
        return request
    }

    private func makeRequest(scale: CGFloat) -> ImageRequest {
        var request = ImageRequest(url: Test.url)
        request.scale = scale
        return request
    }
}

#endif
