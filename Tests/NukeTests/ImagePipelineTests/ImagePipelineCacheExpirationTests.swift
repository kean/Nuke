// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// Spins until the clock the cache stamps entries with has moved past the date
/// the entries stored so far expire on, instead of sleeping for a guessed time.
private func waitForExpiration(after interval: TimeInterval) {
    let deadline = Date.timeIntervalSinceReferenceDate + interval
    while Date.timeIntervalSinceReferenceDate <= deadline {}
}

/// Records what it was asked to store, with the expiration it was given.
private final class ExpirationRecordingCache: ImageCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var _images = [ImageCacheKey: ImageContainer]()
    private var _stored = [(isPreview: Bool, expiration: ImageRequest.CacheExpiration?)]()

    var stored: [(isPreview: Bool, expiration: ImageRequest.CacheExpiration?)] {
        lock.withLock { _stored }
    }

    subscript(key: ImageCacheKey) -> ImageContainer? {
        get { lock.withLock { _images[key] } }
        set {
            lock.withLock {
                _images[key] = newValue
                if let newValue {
                    _stored.append((newValue.isPreview, nil))
                }
            }
        }
    }

    func store(_ image: ImageContainer, for key: ImageCacheKey, expiration: ImageRequest.CacheExpiration) {
        lock.withLock {
            _images[key] = image
            _stored.append((image.isPreview, expiration))
        }
    }

    func removeAll() {
        lock.withLock { _images.removeAll() }
    }
}

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineCacheExpirationTests {
    let dataLoader = MockDataLoader()
    let cache = ImageCache()
    let pipeline: ImagePipeline

    init() {
        let (dataLoader, cache) = (dataLoader, cache)
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
        }
    }

    private func request(_ expiration: ImageRequest.CacheExpiration?) -> ImageRequest {
        var request = Test.request
        request.cacheExpiration = expiration
        return request
    }

    // MARK: Loading

    @Test func imageIsServedFromTheCacheUntilItExpires() async throws {
        // Given
        let request = request(.interval(3600))

        // When
        _ = try await pipeline.image(for: request)
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 1)
        #expect(pipeline.cache[request] != nil)
    }

    @Test func imageIsLoadedAgainOnceItExpires() async throws {
        // Given
        let request = request(.interval(0.001))
        _ = try await pipeline.image(for: request)

        // When
        waitForExpiration(after: 0.001)
        #expect(pipeline.cache[request] == nil)
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func dateExpiresTheImage() async throws {
        // Given
        let request = request(.date(Date(timeIntervalSinceNow: 0.001)))
        _ = try await pipeline.image(for: request)

        // When
        waitForExpiration(after: 0.001)
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func expirationAppliesToProcessedImages() async throws {
        // Given
        var request = request(.interval(0.001))
        request.processors = [MockImageProcessor(id: "1")]
        _ = try await pipeline.image(for: request)

        // When
        waitForExpiration(after: 0.001)

        // Then
        #expect(pipeline.cache[request] == nil)
    }

    @Test func expirationAppliesToAnyRequestForTheImage() async throws {
        // Given the image stored by a request that expires it
        _ = try await pipeline.image(for: request(.interval(0.001)))

        // When
        waitForExpiration(after: 0.001)

        // Then a request with an expiration of its own doesn't see it either
        #expect(pipeline.cache[request(.interval(3600))] == nil)
        #expect(pipeline.cache[request(nil)] == nil)
    }

    // MARK: Cache Default

    @Test func requestWithoutExpirationUsesTheDefaultOfTheCache() async throws {
        // Given
        cache.ttl = -1

        // When
        _ = try await pipeline.image(for: request(nil))

        // Then
        #expect(pipeline.cache[request(nil)] == nil)
    }

    @Test(arguments: [
        ImageRequest.CacheExpiration.never,
        .interval(3600),
        .date(.distantFuture)
    ])
    func expirationOverridesTheDefaultOfTheCache(expiration: ImageRequest.CacheExpiration) async throws {
        // Given
        cache.ttl = -1

        // When
        _ = try await pipeline.image(for: request(expiration))

        // Then
        #expect(pipeline.cache[request(expiration)] != nil)
    }

    // MARK: Expired on Arrival

    @Test(arguments: [
        ImageRequest.CacheExpiration.date(.distantPast),
        .interval(0),
        .interval(-1)
    ])
    func expiredImageIsNotStored(expiration: ImageRequest.CacheExpiration) async throws {
        // When
        _ = try await pipeline.image(for: request(expiration))

        // Then
        #expect(cache.totalCount == 0)
    }

    @Test func expiredImageIsNotHandedToACustomCache() async throws {
        // Given a cache that would keep it for good
        let cache = MockImageCache()
        let pipeline = pipeline.reconfigured { $0.imageCache = cache }

        // When
        _ = try await pipeline.image(for: request(.date(.distantPast)))

        // Then
        #expect(cache.images.isEmpty)
    }

    @Test func expiredImageReplacesTheStoredOne() {
        // Given
        pipeline.cache[request(nil)] = Test.container

        // When
        pipeline.cache[request(.date(.distantPast))] = Test.container

        // Then
        #expect(cache.totalCount == 0)
    }

    // MARK: Cache API

    @Test func subscriptUsesTheExpirationOfTheRequest() {
        // When
        pipeline.cache[request(.interval(0.001))] = Test.container
        waitForExpiration(after: 0.001)

        // Then
        #expect(pipeline.cache[request(nil)] == nil)
    }

    @Test func storeCachedImageUsesTheExpirationOfTheRequest() {
        // Given
        let cache = ExpirationRecordingCache()
        let pipeline = pipeline.reconfigured { $0.imageCache = cache }

        // When
        pipeline.cache.storeCachedImage(Test.container, for: request(.interval(60)), caches: [.memory])

        // Then
        #expect(cache.stored.map(\.expiration) == [.interval(60)])
    }

    @Test func storingAgainReplacesTheExpiration() {
        // Given
        pipeline.cache[request(.interval(0.001))] = Test.container

        // When
        pipeline.cache[request(.interval(3600))] = Test.container
        waitForExpiration(after: 0.001)

        // Then
        #expect(pipeline.cache[request(nil)] != nil)
    }

    @Test func disabledMemoryCacheWritesStayDisabled() async throws {
        // Given
        var request = request(.interval(60))
        request.options.insert(.disableMemoryCacheWrites)

        // When
        _ = try await pipeline.image(for: request)

        // Then
        #expect(cache.totalCount == 0)
    }

    // MARK: Custom Caches

    @Test func cacheThatDoesNotImplementExpirationStoresTheImageWithoutIt() async throws {
        // Given
        let cache = MockImageCache()
        let pipeline = pipeline.reconfigured { $0.imageCache = cache }
        let request = request(.interval(0.001))

        // When
        _ = try await pipeline.image(for: request)
        waitForExpiration(after: 0.001)

        // Then
        #expect(cache.writeCount == 1)
        #expect(pipeline.cache[request] != nil)
    }

    @Test func requestWithoutExpirationDoesNotCallTheExpiringStore() async throws {
        // Given
        let cache = ExpirationRecordingCache()
        let pipeline = pipeline.reconfigured { $0.imageCache = cache }

        // When
        _ = try await pipeline.image(for: request(nil))

        // Then
        #expect(cache.stored.count == 1)
        #expect(cache.stored.first?.expiration == nil)
    }

    // MARK: Previews

    @Test func previewsAreStoredWithTheExpirationOfTheRequest() async throws {
        // Given
        let dataLoader = MockProgressiveDataLoader()
        let cache = ExpirationRecordingCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.isStoringPreviewsInMemoryCache = true
        }

        // When
        let task = pipeline.imageTask(with: request(.interval(60)))
        for try await _ in task.previews {
            dataLoader.resume()
        }
        _ = try await task.response

        // Then both the previews and the final image have it
        let stored = cache.stored
        #expect(stored.count > 1)
        #expect(stored.contains { $0.isPreview })
        #expect(stored.last?.isPreview == false)
        #expect(stored.allSatisfy { $0.expiration == .interval(60) })
    }

    // MARK: Coalescing

    /// Loads the requests through one task and returns what the entry got.
    private func expiration(ofCoalesced requests: [ImageRequest]) async throws -> ImageRequest.CacheExpiration? {
        let cache = ExpirationRecordingCache()
        let pipeline = pipeline.reconfigured { $0.imageCache = cache }
        let tasks = await startSuspended(for: pipeline, count: requests.count) {
            requests.map { pipeline.imageTask(with: $0) }
        }
        dataLoader.isSuspended = false
        for task in tasks {
            _ = try await task.response
        }
        #expect(dataLoader.createdTaskCount == 1)
        #expect(cache.stored.count == 1)
        return cache.stored.first?.expiration
    }

    @Test func expirationDoesNotStopCoalescing() async throws {
        let expiration = try await expiration(ofCoalesced: [request(.interval(60)), request(.interval(120))])
        #expect(expiration == .interval(60))
    }

    @Test func soonestExpirationWinsInAnyOrder() async throws {
        let expiration = try await expiration(ofCoalesced: [request(.interval(120)), request(.interval(60))])
        #expect(expiration == .interval(60))
    }

    @Test func taskThatJoinedBringsItsExpiration() async throws {
        // Given a load started by a request that has no expiration
        let expiration = try await expiration(ofCoalesced: [request(nil), request(.interval(60))])

        // Then the entry doesn't outlive the request that joined it
        #expect(expiration == .interval(60))
    }

    @Test func requestWithoutExpirationHasNoSay() async throws {
        let expiration = try await expiration(ofCoalesced: [request(.interval(60)), request(nil)])
        #expect(expiration == .interval(60))
    }

    @Test func neverLosesToAnyExpiration() async throws {
        let expiration = try await expiration(ofCoalesced: [request(.never), request(.interval(60))])
        #expect(expiration == .interval(60))
    }

    @Test func intervalAndDateAreCompared() async throws {
        let date = Date(timeIntervalSinceNow: 60)
        let expiration = try await expiration(ofCoalesced: [request(.interval(3600)), request(.date(date))])
        #expect(expiration == .date(date))
    }

    @Test func taskThatAppliesOneMoreProcessorHasASay() async throws {
        // Given a task that stores the processed image, and a task that waits
        // for it to apply one more processor
        let cache = ExpirationRecordingCache()
        let pipeline = pipeline.reconfigured { $0.imageCache = cache }
        var first = request(nil)
        first.processors = [MockImageProcessor(id: "1")]
        var second = request(.interval(60))
        second.processors = [MockImageProcessor(id: "1"), MockImageProcessor(id: "2")]

        // When
        let tasks = await startSuspended(for: pipeline, count: 2) {
            [pipeline.imageTask(with: first), pipeline.imageTask(with: second)]
        }
        dataLoader.isSuspended = false
        for task in tasks {
            _ = try await task.response
        }

        // Then neither of the entries it reads outlives what it asked for
        #expect(cache.stored.count == 2)
        #expect(cache.stored.allSatisfy { $0.expiration == .interval(60) })
    }

    // MARK: Identity

    @Test func expirationIsNotPartOfTheCacheKey() {
        #expect(ImageCacheKey(request: request(.interval(60))) == ImageCacheKey(request: request(nil)))
        #expect(pipeline.cache.makeDataCacheKey(for: request(.interval(60))) == pipeline.cache.makeDataCacheKey(for: request(nil)))
    }
}

@Suite(.timeLimit(.minutes(5)))
struct ImageCachePerEntryExpirationTests {
    let cache = ImageCache()
    let key = ImageCacheKey(key: "a")

    @Test func expirationIsNilByDefault() {
        #expect(Test.request.cacheExpiration == nil)
    }

    @Test func requestKeepsTheExpiration() {
        // Given
        var request = Test.request
        request.cacheExpiration = .interval(60)

        // When a copy is mutated
        var copy = request
        copy.cacheExpiration = .never
        var cleared = request
        cleared.priority = .high

        // Then
        #expect(request.cacheExpiration == .interval(60))
        #expect(copy.cacheExpiration == .never)
        #expect(cleared.cacheExpiration == .interval(60))
    }

    @Test func assigningUserInfoKeepsTheExpiration() {
        // Given
        var request = Test.request
        request.cacheExpiration = .interval(60)

        // When
        request.userInfo = [:]

        // Then
        #expect(request.cacheExpiration == .interval(60))
    }

    @Test func expirationDate() {
        // Given
        let date = Date(timeIntervalSinceNow: 60)

        // Then
        #expect(ImageRequest.CacheExpiration.never.expirationDate == nil)
        #expect(ImageRequest.CacheExpiration.date(date).expirationDate.map { abs($0.timeIntervalSince(date)) < 0.1 } == true)
        #expect(ImageRequest.CacheExpiration.interval(60).expirationDate.map { abs($0.timeIntervalSince(date)) < 10 } == true)
    }

    @Test func storedImageCountsAgainstTheCost() {
        // When
        cache.store(Test.container, for: key, expiration: .interval(60))

        // Then
        #expect(cache[key] != nil)
        #expect(cache.totalCount == 1)
        #expect(cache.totalCost == Test.container.memoryCost)
    }

    @Test func expirationTakesPrecedenceOverTheDefault() {
        // Given
        cache.ttl = 3600

        // When
        cache.store(Test.container, for: key, expiration: .interval(-1))

        // Then
        #expect(cache[key] == nil)
    }

    @Test func neverOverridesTheDefault() {
        // Given
        cache.ttl = -1

        // When
        cache.store(Test.container, for: key, expiration: .never)

        // Then
        #expect(cache[key] != nil)
    }

    @Test func pastDateExpiresOnRead() {
        // When
        cache.store(Test.container, for: key, expiration: .date(.distantPast))

        // Then
        #expect(cache[key] == nil)
        #expect(cache.totalCount == 0)
    }

    @Test func imageTooLargeForTheCacheIsNotStored() {
        // Given
        let cache = ImageCache(costLimit: 1)

        // When
        cache.store(Test.container, for: key, expiration: .interval(60))

        // Then
        #expect(cache[key] == nil)
    }
}
