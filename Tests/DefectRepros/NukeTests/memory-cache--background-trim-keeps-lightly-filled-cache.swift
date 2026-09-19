// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

// SUSPECTED BUG (docs vs behavior, iOS/tvOS/visionOS only): entering the
// background removes nothing from a cache that is less than 10% full.
//
// Docs: `ImageCache` – "On iOS, tvOS, and visionOS, it also automatically
// removes *most* stored elements when the app enters the background" (same
// sentence in cache-layers.md; performance-guide.md: "removes a portion of its
// contents"; CHANGELOG for Nuke 12: "it clears 90% of the used RAM when
// entering the background").
//
// `Cache.clearCacheOnEnterBackground()` (Sources/Nuke/Caching/Cache.swift:185)
// trims to 10% of the *limits* – `_trim(toCost: costLimit * 0.1)` and
// `_trim(toCount: countLimit * 0.1)` – rather than to 10% of the *contents*.
// With the default limits (a cost limit of up to 768 MB and a count limit of
// `Int.max`), an app holding less than ~77 MB of images keeps every one of
// them in the background, and one holding 100 MB frees only a quarter.
//
// Expected: after the notification, at most a minority of the 5 images
// remain ("removes most stored elements").
// Actual: all 5 remain, because they cost 50 of a 1000-byte limit.
//
// Posts `UIApplication.didEnterBackgroundNotification` the way
// `ImageCacheTests.someImagesAreRemovedOnDidEnterBackground()` does.
@Suite(.timeLimit(.minutes(5)))
struct MemoryCacheBackgroundTrimRepro {
    private func container(cost: Int) -> ImageContainer {
        ImageContainer(image: PlatformImage(), data: Data(count: cost - 1))
    }

    @MainActor
    @Test func mostImagesAreRemovedWhenEnteringTheBackground() async {
        // Given a cache whose background observer is registered – the
        // registration is asynchronous, so wait until a cache that is full by
        // count gets trimmed
        let cache = ImageCache(costLimit: 1000, countLimit: 20)
        cache.entryCostLimit = 1
        for index in 0..<20 {
            cache[ImageCacheKey(key: "canary-\(index)")] = container(cost: 1)
        }
        while cache.totalCount == 20 {
            await Task.yield()
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        }
        cache.removeAll()
        cache.countLimit = .max

        // Given 5 images worth 50 of the 1000-byte limit
        for index in 0..<5 {
            cache[ImageCacheKey(key: "image-\(index)")] = container(cost: 10)
        }

        // When
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        // Then most of them are removed
        #expect(cache.totalCount <= 2) // fails: 5
    }
}
#endif
