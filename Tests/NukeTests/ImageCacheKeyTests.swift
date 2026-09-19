// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
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

    // MARK: - Collisions

    /// A custom key and a request key are separate namespaces, even when the
    /// custom string is the request's URL.
    @Test func customKeyDoesNotMatchARequestForTheSameString() {
        let url = "https://example.com/image.png"
        let customKey = ImageCacheKey(key: url)
        let requestKey = ImageCacheKey(request: ImageRequest(url: URL(string: url)))
        #expect(customKey != requestKey)

        // Given
        let cache = ImageCache()
        cache[customKey] = ImageContainer(image: PlatformImage(), data: Data([1]))
        cache[requestKey] = ImageContainer(image: PlatformImage(), data: Data([2]))

        // Then
        #expect(cache.totalCount == 2)
        #expect(cache[customKey]?.data == Data([1]))
        #expect(cache[requestKey]?.data == Data([2]))
    }

    @Test func emptyCustomKeyIsAValidKey() {
        let cache = ImageCache()
        cache[ImageCacheKey(key: "")] = ImageContainer(image: PlatformImage())
        #expect(cache[ImageCacheKey(key: "")] != nil)
        #expect(cache[ImageCacheKey(request: ImageRequest(url: nil))] == nil)
    }

    @Test func processorCountIsPartOfTheKey() {
        let processor = MockImageProcessor(id: "1")
        let lhs = ImageCacheKey(request: ImageRequest(url: Test.url, processors: [processor]))
        let rhs = ImageCacheKey(request: ImageRequest(url: Test.url, processors: [processor, processor]))
        #expect(lhs != rhs)
    }

    // MARK: - Request Fields

    @Test func thumbnailIsPartOfTheKey() {
        // Given
        func request(thumbnail: ImageRequest.ThumbnailOptions?) -> ImageRequest {
            var request = ImageRequest(url: Test.url)
            request.thumbnail = thumbnail
            return request
        }
        let none = ImageCacheKey(request: request(thumbnail: nil))
        let small = ImageCacheKey(request: request(thumbnail: .init(maxPixelSize: 100)))
        let large = ImageCacheKey(request: request(thumbnail: .init(maxPixelSize: 400)))
        let smallAgain = ImageCacheKey(request: request(thumbnail: .init(maxPixelSize: 100)))

        // Then
        #expect(none != small)
        #expect(small != large)
        #expect(small == smallAgain)
        #expect(small.hashValue == smallAgain.hashValue)
    }

    /// The key copies what it needs from the request, so changing the request
    /// afterwards doesn't change a key made from it.
    @Test func keyIsUnaffectedByLaterChangesToTheRequest() {
        // Given
        var request = ImageRequest(url: Test.url)
        let key = ImageCacheKey(request: request)

        // When
        request.processors = [MockImageProcessor(id: "1")]
        request.scale = 3
        request.thumbnail = .init(maxPixelSize: 50)
        request.imageID = "other"

        // Then
        #expect(key == ImageCacheKey(request: ImageRequest(url: Test.url)))
        #expect(key != ImageCacheKey(request: request))
    }
}
