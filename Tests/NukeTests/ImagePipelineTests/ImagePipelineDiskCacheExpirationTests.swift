// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// Records the expiration of each write, and honors nothing.
private final class ExpirationRecordingDataCache: DataCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var _data = [String: Data]()
    private var _stored = [(key: String, expiration: ImageRequest.CacheExpiration?)]()
    var stubbedExpirationDate: Date?

    var stored: [(key: String, expiration: ImageRequest.CacheExpiration?)] {
        lock.withLock { _stored }
    }

    func cachedData(for key: String) -> Data? {
        lock.withLock { _data[key] }
    }

    func containsData(for key: String) -> Bool {
        lock.withLock { _data[key] != nil }
    }

    func storeData(_ data: Data, for key: String) {
        lock.withLock {
            _data[key] = data
            _stored.append((key, nil))
        }
    }

    func storeData(_ data: Data, for key: String, expiration: ImageRequest.CacheExpiration) {
        lock.withLock {
            _data[key] = data
            _stored.append((key, expiration))
        }
    }

    func expirationDate(for key: String) -> Date? {
        stubbedExpirationDate
    }

    func removeData(for key: String) {
        lock.withLock { _data[key] = nil }
    }

    func removeAll() {
        lock.withLock { _data.removeAll() }
    }
}

/// Records the expiration of each image it is asked to store.
private final class ExpirationRecordingImageCache: ImageCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var _images = [ImageCacheKey: ImageContainer]()
    private var _stored = [ImageRequest.CacheExpiration?]()

    var stored: [ImageRequest.CacheExpiration?] {
        lock.withLock { _stored }
    }

    subscript(key: ImageCacheKey) -> ImageContainer? {
        get { lock.withLock { _images[key] } }
        set {
            lock.withLock {
                _images[key] = newValue
                _stored.append(nil)
            }
        }
    }

    func store(_ image: ImageContainer, for key: ImageCacheKey, expiration: ImageRequest.CacheExpiration) {
        lock.withLock {
            _images[key] = image
            _stored.append(expiration)
        }
    }

    func removeAll() {
        lock.withLock { _images.removeAll() }
    }
}

/// Runs the pipeline with a real ``DataCache`` and no memory cache, so that
/// the only thing that can stop a request from reaching `dataLoader` is what
/// is on the disk.
@Suite(.timeLimit(.minutes(5)))
final class ImagePipelineDiskCacheExpirationTests {
    let dataLoader = MockDataLoader()
    let dataCache: DataCache
    let pipeline: ImagePipeline

    init() throws {
        let dataLoader = dataLoader
        let dataCache = try DataCache(path: makeUniqueDirectoryURL())
        self.dataCache = dataCache
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: dataCache.path)
    }

    private func request(_ expiration: ImageRequest.CacheExpiration?) -> ImageRequest {
        var request = Test.request
        request.cacheExpiration = expiration
        return request
    }

    private func waitForExpiration(of request: ImageRequest) throws {
        let key = pipeline.cache.makeDataCacheKey(for: request)
        let date = try #require(dataCache.expirationDate(for: key))
        while Date() <= date {}
    }

    // MARK: Loading

    @Test func imageIsServedFromTheDiskUntilItExpires() async throws {
        // Given
        let request = request(.interval(3600))

        // When
        _ = try await pipeline.image(for: request)
        await dataCache.flush()
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func expiredDiskEntryIsLoadedAgain() async throws {
        // Given
        let request = request(.interval(0.01))
        _ = try await pipeline.image(for: request)
        await dataCache.flush()

        // When
        try waitForExpiration(of: request)
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(dataLoader.createdTaskCount == 2)
        #expect(response.cacheType == nil)
    }

    @Test func expiredEntryInTheStagingAreaIsLoadedAgain() async throws {
        // Given
        let request = request(.interval(0.01))
        _ = try await pipeline.image(for: request)

        // When
        try waitForExpiration(of: request)
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func expiredEntryHoldsBackAnyRequestForTheImage() async throws {
        // Given
        let request = request(.interval(0.01))
        _ = try await pipeline.image(for: request)

        // When
        try waitForExpiration(of: request)
        _ = try await pipeline.image(for: self.request(nil))

        // Then
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func loadingAgainStoresAFreshEntry() async throws {
        // Given an image that expired, and that was loaded again
        let request = request(.interval(3600))
        pipeline.cache.storeCachedData(Test.data, for: self.request(.date(.distantPast)))
        _ = try await pipeline.image(for: request)

        // When
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func requestThatOnlyReadsTheCacheFailsOnAnExpiredEntry() async throws {
        // Given
        pipeline.cache.storeCachedData(Test.data, for: request(.interval(0.01)))
        try waitForExpiration(of: request(nil))

        // When
        var request = request(nil)
        request.options.insert(.returnCacheDataDontLoad)

        // Then
        await #expect(throws: ImagePipeline.Error.dataMissingInCache) {
            try await self.pipeline.image(for: request)
        }
    }

    @Test func dataRequestsSeeTheExpirationToo() async throws {
        // Given
        let request = request(.interval(0.01))
        _ = try await pipeline.data(for: request)
        try waitForExpiration(of: request)

        // When
        _ = try await pipeline.data(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 2)
    }

    // MARK: Data Cache Policy

    @Test func encodedImagesExpire() async throws {
        // Given
        let dataCache = dataCache
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }
        let request = request(.interval(0.01))
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()
        await dataCache.flush()
        #expect(dataCache.totalCount == 1)

        // When
        try waitForExpiration(of: request)
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func allEntriesOfAProcessedImageExpire() async throws {
        // Given
        let dataCache = dataCache
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }
        var request = request(.interval(0.01))
        request.processors = [MockImageProcessor(id: "1")]
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()
        await dataCache.flush()
        #expect(dataCache.totalCount == 2)

        // When
        try waitForExpiration(of: request)
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 2)
    }

    // MARK: Cache API

    @Test func storeCachedDataUsesTheExpirationOfTheRequest() {
        // When
        pipeline.cache.storeCachedData(Test.data, for: request(.interval(3600)))

        // Then
        #expect(dataCache.expirationDate(for: pipeline.cache.makeDataCacheKey(for: request(nil))) != nil)
    }

    @Test func storeCachedImageUsesTheExpirationOfTheRequest() {
        // When
        pipeline.cache.storeCachedImage(Test.container, for: request(.interval(3600)), caches: [.disk])

        // Then
        #expect(dataCache.expirationDate(for: pipeline.cache.makeDataCacheKey(for: request(nil))) != nil)
    }

    @Test func expiredDataReplacesTheStoredEntry() {
        // Given
        pipeline.cache.storeCachedData(Test.data, for: request(nil))

        // When
        pipeline.cache.storeCachedData(Test.data, for: request(.date(.distantPast)))

        // Then
        #expect(pipeline.cache.cachedData(for: request(nil)) == nil)
    }

    @Test func containsDataSeesTheExpiration() {
        // When
        pipeline.cache.storeCachedData(Test.data, for: request(.date(.distantPast)))

        // Then
        #expect(!pipeline.cache.containsData(for: request(nil)))
        #expect(!pipeline.cache.containsCachedImage(for: request(nil)))
    }

    // MARK: Custom Caches

    @Test func cacheThatDoesNotImplementExpirationStoresTheDataWithoutIt() async throws {
        // Given
        let dataCache = MockDataCache()
        let pipeline = pipeline.reconfigured { $0.dataCache = dataCache }

        // When
        _ = try await pipeline.image(for: request(.interval(60)))

        // Then
        #expect(dataCache.writeCount == 1)
    }

    @Test func expiredDataIsNotHandedToACustomCache() async throws {
        // Given a cache that would keep it for good
        let dataCache = MockDataCache()
        let pipeline = pipeline.reconfigured { $0.dataCache = dataCache }

        // When
        _ = try await pipeline.image(for: request(.date(.distantPast)))

        // Then
        #expect(dataCache.store.isEmpty)
    }

    @Test func requestWithoutExpirationDoesNotCallTheExpiringStore() async throws {
        // Given
        let dataCache = ExpirationRecordingDataCache()
        let pipeline = pipeline.reconfigured { $0.dataCache = dataCache }

        // When
        _ = try await pipeline.image(for: request(nil))

        // Then
        #expect(dataCache.stored.count == 1)
        #expect(dataCache.stored.first?.expiration == nil)
    }

    // MARK: Coalescing

    /// Loads the requests through one task and returns what the entry got.
    private func expiration(ofCoalesced requests: [ImageRequest]) async throws -> ImageRequest.CacheExpiration? {
        let dataCache = ExpirationRecordingDataCache()
        let pipeline = pipeline.reconfigured { $0.dataCache = dataCache }
        let tasks = await startSuspended(for: pipeline, count: requests.count) {
            requests.map { pipeline.imageTask(with: $0) }
        }
        dataLoader.isSuspended = false
        for task in tasks {
            _ = try await task.response
        }
        #expect(dataLoader.createdTaskCount == 1)
        #expect(dataCache.stored.count == 1)
        return dataCache.stored.first?.expiration
    }

    @Test func soonestExpirationOfTheTasksSharingTheDownloadWins() async throws {
        let expiration = try await expiration(ofCoalesced: [request(.interval(120)), request(.interval(60))])
        #expect(expiration == .interval(60))
    }

    @Test func taskThatJoinedTheDownloadBringsItsExpiration() async throws {
        let expiration = try await expiration(ofCoalesced: [request(nil), request(.interval(60))])
        #expect(expiration == .interval(60))
    }

    @Test func tasksThatOnlyShareTheDownloadStillShareTheEntry() async throws {
        // Given requests that end up with different images, and the same data
        var first = request(nil)
        first.processors = [MockImageProcessor(id: "1")]
        var second = request(.interval(60))
        second.processors = [MockImageProcessor(id: "2")]

        // When
        let expiration = try await expiration(ofCoalesced: [first, second])

        // Then
        #expect(expiration == .interval(60))
    }

    @Test func encodedImageGetsTheSoonestExpiration() async throws {
        // Given
        let dataCache = ExpirationRecordingDataCache()
        let pipeline = pipeline.reconfigured {
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeEncodedImages
        }

        // When
        let tasks = await startSuspended(for: pipeline, count: 2) {
            [pipeline.imageTask(with: request(.interval(120))), pipeline.imageTask(with: request(.interval(60)))]
        }
        dataLoader.isSuspended = false
        for task in tasks {
            _ = try await task.response
        }
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(dataCache.stored.map(\.expiration) == [.interval(60)])
    }

    // MARK: Delegate

    @Test func dataTheDelegateChangedKeepsTheExpiration() async throws {
        // Given
        let dataCache = ExpirationRecordingDataCache()
        let delegate = MockCachingDelegate()
        delegate.willCacheTransform = { $0 + [1] }
        let pipeline = pipeline.reconfigured(delegate: delegate) { $0.dataCache = dataCache }

        // When
        _ = try await pipeline.image(for: request(.interval(60)))

        // Then
        #expect(dataCache.stored.map(\.expiration) == [.interval(60)])
        #expect(dataCache.cachedData(for: pipeline.cache.makeDataCacheKey(for: request(nil))) == Test.data + [1])
    }

    @Test func taskCancelledWhileTheDelegateRunsKeepsItsExpiration() async throws {
        // Given a delegate that holds the write until the task is gone
        let dataCache = ExpirationRecordingDataCache()
        let delegate = BlockingWillCacheDelegate()
        let pipeline = pipeline.reconfigured(delegate: delegate) { $0.dataCache = dataCache }

        // When
        let task = pipeline.imageTask(with: request(.interval(60)))
        await delegate.didStart.wait()
        task.cancel()
        _ = try? await task.response
        delegate.resume()

        // Then the data isn't stored with no expiration
        try await dataCache.waitForWrite()
        #expect(dataCache.stored.map(\.expiration) == [.interval(60)])
    }

    // MARK: Memory Cache

    /// Returns what an image read from a disk entry that expires on `date` is
    /// stored with in the memory cache.
    private func memoryExpiration(
        of request: ImageRequest,
        diskEntryExpiringOn date: Date?,
        for diskRequest: ImageRequest? = nil,
        delegate: (any ImagePipeline.Delegate)? = nil
    ) async throws -> [ImageRequest.CacheExpiration?] {
        let imageCache = ExpirationRecordingImageCache()
        let pipeline = pipeline.reconfigured(delegate: delegate) { $0.imageCache = imageCache }
        var diskRequest = diskRequest ?? request
        diskRequest.cacheExpiration = date.map { .date($0) }
        pipeline.cache.storeCachedData(Test.data, for: diskRequest)
        _ = try await pipeline.image(for: request)
        #expect(dataLoader.createdTaskCount == 0)
        return imageCache.stored
    }

    @Test func imageReadFromTheDiskDoesNotOutliveTheEntry() async throws {
        // Given
        let date = Date(timeIntervalSinceNow: 60)

        // When the request would keep it for longer
        let stored = try await memoryExpiration(of: request(.interval(3600)), diskEntryExpiringOn: date)

        // Then
        try #require(stored.count == 1)
        let expirationDate = try #require(stored[0]?.expirationDate)
        #expect(abs(expirationDate.timeIntervalSince(date)) < 0.001)
    }

    @Test func imageReadFromTheDiskCanExpireBeforeTheEntry() async throws {
        // When
        let stored = try await memoryExpiration(of: request(.interval(60)), diskEntryExpiringOn: Date(timeIntervalSinceNow: 3600))

        // Then
        #expect(stored == [.interval(60)])
    }

    @Test func requestWithoutExpirationInheritsTheOneOfTheEntry() async throws {
        // Given
        let date = Date(timeIntervalSinceNow: 60)

        // When
        let stored = try await memoryExpiration(of: request(nil), diskEntryExpiringOn: date)

        // Then
        let expirationDate = try #require(stored.first??.expirationDate)
        #expect(abs(expirationDate.timeIntervalSince(date)) < 0.001)
    }

    @Test func imageReadFromAnEntryWithoutExpirationUsesTheRequest() async throws {
        // When
        let stored = try await memoryExpiration(of: request(nil), diskEntryExpiringOn: nil)

        // Then
        #expect(stored == [nil])
    }

    @Test func processedImageDoesNotOutliveTheOriginalData() async throws {
        // Given
        let date = Date(timeIntervalSinceNow: 60)
        var request = request(.interval(3600))
        request.processors = [MockImageProcessor(id: "1")]

        // When the original data is on the disk
        let stored = try await memoryExpiration(of: request, diskEntryExpiringOn: date, for: self.request(nil))

        // Then
        let expirationDate = try #require(stored.first??.expirationDate)
        #expect(abs(expirationDate.timeIntervalSince(date)) < 0.001)
    }

    @Test func thumbnailDoesNotOutliveTheOriginalData() async throws {
        // Given
        let date = Date(timeIntervalSinceNow: 60)
        var request = request(nil)
        request.thumbnail = .init(maxPixelSize: 10)

        // When the original data is on the disk
        let stored = try await memoryExpiration(of: request, diskEntryExpiringOn: date, for: self.request(nil))

        // Then
        let expirationDate = try #require(stored.first??.expirationDate)
        #expect(abs(expirationDate.timeIntervalSince(date)) < 0.001)
    }

    @Test func imageFromTheNetworkDoesNotReadTheEntry() async throws {
        // Given
        let imageCache = ExpirationRecordingImageCache()
        let dataCache = ExpirationRecordingDataCache()
        dataCache.stubbedExpirationDate = Date(timeIntervalSinceNow: 60)
        let pipeline = pipeline.reconfigured {
            $0.imageCache = imageCache
            $0.dataCache = dataCache
        }

        // When
        _ = try await pipeline.image(for: request(nil))

        // Then
        #expect(imageCache.stored == [nil])
    }
}

/// Holds `willCache` until it's told to continue.
private final class BlockingWillCacheDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    let didStart = TestExpectation()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isResumed = false

    @ImagePipelineActor
    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                self.continuation = continuation
                return isResumed
            }
            didStart.fulfill()
            if shouldResume { continuation.resume() }
        }
        return data
    }

    func resume() {
        lock.withLock {
            isResumed = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }?.resume()
    }
}

extension ExpirationRecordingDataCache {
    fileprivate func waitForWrite() async throws {
        for _ in 0..<1000 where stored.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
