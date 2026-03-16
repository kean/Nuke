// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(2)))
struct ImageCacheKeyTests {
    @Test func customKeyEquality() {
        let key1 = ImageCacheKey(key: "test-key")
        let key2 = ImageCacheKey(key: "test-key")
        #expect(key1 == key2)
    }

    @Test func customKeyInequality() {
        let key1 = ImageCacheKey(key: "key-a")
        let key2 = ImageCacheKey(key: "key-b")
        #expect(key1 != key2)
    }

    @Test func requestKeyEquality() {
        let request = ImageRequest(url: URL(string: "https://example.com/image.png")!)
        let key1 = ImageCacheKey(request: request)
        let key2 = ImageCacheKey(request: request)
        #expect(key1 == key2)
    }

    @Test func requestKeyDiffers() {
        let request1 = ImageRequest(url: URL(string: "https://example.com/a.png")!)
        let request2 = ImageRequest(url: URL(string: "https://example.com/b.png")!)
        let key1 = ImageCacheKey(request: request1)
        let key2 = ImageCacheKey(request: request2)
        #expect(key1 != key2)
    }

    @Test func customKeyHashable() {
        let key1 = ImageCacheKey(key: "same")
        let key2 = ImageCacheKey(key: "same")
        #expect(key1.hashValue == key2.hashValue)
    }

    @Test func customAndRequestKeysDiffer() {
        let customKey = ImageCacheKey(key: "custom")
        let requestKey = ImageCacheKey(request: ImageRequest(url: URL(string: "https://example.com/custom")!))
        #expect(customKey != requestKey)
    }

    @Test func requestKeyHashable() {
        let request = ImageRequest(url: URL(string: "https://example.com/image.png")!)
        let key1 = ImageCacheKey(request: request)
        let key2 = ImageCacheKey(request: request)
        #expect(key1.hashValue == key2.hashValue)
    }

    @Test func customKeyCanBeUsedInSet() {
        let key1 = ImageCacheKey(key: "a")
        let key2 = ImageCacheKey(key: "b")
        let key3 = ImageCacheKey(key: "a")
        let set: Set<ImageCacheKey> = [key1, key2, key3]
        #expect(set.count == 2)
    }

    @Test func customKeyCanBeUsedAsDictionaryKey() {
        var dict = [ImageCacheKey: String]()
        dict[ImageCacheKey(key: "k1")] = "value1"
        dict[ImageCacheKey(key: "k2")] = "value2"
        #expect(dict[ImageCacheKey(key: "k1")] == "value1")
        #expect(dict[ImageCacheKey(key: "k2")] == "value2")
        #expect(dict[ImageCacheKey(key: "k3")] == nil)
    }
}
