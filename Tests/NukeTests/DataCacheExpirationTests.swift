// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

private let attribute = "com.github.kean.Nuke.expiration"

/// The staged and the flushed paths are separate code, and each test runs on
/// both.
enum DataCacheExpirationStorage: CaseIterable, Sendable {
    case staged
    case flushed
}

@Suite(.timeLimit(.minutes(5)))
final class DataCacheExpirationTests {
    let data = Data([1, 2, 3])
    let cache: DataCache

    init() throws {
        cache = try DataCache(path: makeUniqueDirectoryURL())
    }

    deinit {
        try? FileManager.default.removeItem(at: cache.path)
    }

    private func store(_ expiration: ImageRequest.CacheExpiration, for key: String = "a", in storage: DataCacheExpirationStorage) async {
        cache.storeData(data, for: key, expiration: expiration)
        if storage == .flushed {
            await cache.flush()
        }
    }

    // MARK: Reading

    @Test(arguments: DataCacheExpirationStorage.allCases)
    func entryIsReadUntilItExpires(storage: DataCacheExpirationStorage) async {
        // When
        await store(.interval(3600), in: storage)

        // Then
        #expect(cache.cachedData(for: "a") == data)
        #expect(cache.containsData(for: "a"))
    }

    @Test(arguments: DataCacheExpirationStorage.allCases)
    func expiredEntryReadsAsMissing(storage: DataCacheExpirationStorage) async {
        // When
        await store(.date(.distantPast), in: storage)

        // Then
        #expect(cache.cachedData(for: "a") == nil)
        #expect(!cache.containsData(for: "a"))
    }

    @Test(arguments: DataCacheExpirationStorage.allCases)
    func entryExpiresWithTheTimePassing(storage: DataCacheExpirationStorage) async throws {
        // Given
        await store(.interval(0.01), in: storage)
        let date = try #require(cache.expirationDate(for: "a"))

        // When
        while Date() <= date {}

        // Then
        #expect(cache.cachedData(for: "a") == nil)
        #expect(!cache.containsData(for: "a"))
    }

    @Test(arguments: DataCacheExpirationStorage.allCases)
    func expirationDateIsReadBack(storage: DataCacheExpirationStorage) async throws {
        // Given
        let date = Date(timeIntervalSinceNow: 3600)

        // When
        await store(.date(date), in: storage)

        // Then
        let expirationDate = try #require(cache.expirationDate(for: "a"))
        #expect(abs(expirationDate.timeIntervalSince(date)) < 0.001)
    }

    @Test(arguments: DataCacheExpirationStorage.allCases)
    func neverHasNoExpirationDate(storage: DataCacheExpirationStorage) async {
        // When
        await store(.never, in: storage)

        // Then
        #expect(cache.cachedData(for: "a") == data)
        #expect(cache.expirationDate(for: "a") == nil)
    }

    @Test func entriesHaveNoExpirationDateByDefault() async {
        // Given
        cache.storeData(data, for: "a")
        #expect(cache.expirationDate(for: "a") == nil)

        // When
        await cache.flush()

        // Then
        #expect(cache.expirationDate(for: "a") == nil)
        #expect(cache.expirationDate(for: "missing") == nil)
    }

    @Test func removedEntryHasNoExpirationDate() async {
        // Given
        await store(.interval(3600), in: .flushed)

        // When
        cache.removeData(for: "a")

        // Then
        #expect(cache.expirationDate(for: "a") == nil)
    }

    // MARK: Writing

    @Test(arguments: DataCacheExpirationStorage.allCases)
    func storingAgainReplacesTheExpiration(storage: DataCacheExpirationStorage) async {
        // Given
        await store(.date(.distantPast), in: .flushed)

        // When
        await store(.interval(3600), in: storage)

        // Then
        #expect(cache.cachedData(for: "a") == data)
    }

    @Test(arguments: DataCacheExpirationStorage.allCases)
    func storingWithoutExpirationClearsIt(storage: DataCacheExpirationStorage) async {
        // Given
        await store(.date(.distantPast), in: .flushed)

        // When
        cache.storeData(data, for: "a")
        if storage == .flushed {
            await cache.flush()
        }

        // Then
        #expect(cache.cachedData(for: "a") == data)
        #expect(cache.expirationDate(for: "a") == nil)
    }

    @Test func fileLeftBehindDoesNotPassItsExpirationOn() async throws {
        // Given the temporary file of a process that died before the rename
        await store(.interval(3600), for: "b", in: .flushed)
        let url = try #require(cache.url(for: "a"))
        let tempURL = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".tmp")
        try data.write(to: tempURL)
        var expired: TimeInterval = 0
        #expect(setxattr(tempURL.path, attribute, &expired, MemoryLayout<TimeInterval>.size, 0, 0) == 0)

        // When
        cache.storeData(data, for: "a")
        await cache.flush()

        // Then
        #expect(cache.cachedData(for: "a") == data)
    }

    // MARK: Persistence

    @Test func expirationSurvivesARelaunch() async throws {
        // Given
        let date = Date(timeIntervalSinceNow: 3600)
        await store(.date(date), in: .flushed)
        await store(.date(.distantPast), for: "b", in: .flushed)

        // When
        let relaunched = try DataCache(path: cache.path)

        // Then
        #expect(relaunched.expirationDate(for: "a") != nil)
        #expect(relaunched.cachedData(for: "a") == data)
        #expect(relaunched.cachedData(for: "b") == nil)
    }

    @Test func updatingTheAccessDateKeepsTheExpiration() async throws {
        // Given
        await store(.interval(3600), in: .flushed)
        let date = cache.expirationDate(for: "a")

        // When the read touches the access date
        #expect(cache.cachedData(for: "a") == data)
        await cache.flush()

        // Then
        #expect(cache.accessDateUpdateCount == 1)
        #expect(cache.expirationDate(for: "a") == date)
    }

    @Test func readingTheExpirationDoesNotCountAsAnAccess() async throws {
        // Given
        await store(.interval(3600), in: .flushed)
        let url = try #require(cache.url(for: "a"))
        var values = URLResourceValues()
        values.contentAccessDate = Date(timeIntervalSinceNow: -3600)
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        var fresh = url
        fresh.removeAllCachedResourceValues()
        let before = try fresh.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate

        // When
        _ = cache.expirationDate(for: "a")
        _ = cache.containsData(for: "a")

        // Then the LRU sweep ranks the entry where it was
        fresh.removeAllCachedResourceValues()
        #expect(try fresh.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate == before)
    }

    @Test func removingEverythingLeavesTheCacheAbleToExpireEntries() async throws {
        // Given
        await store(.interval(3600), for: "a", in: .flushed)
        cache.removeAll()
        await cache.flush()

        // When
        await store(.date(.distantPast), for: "b", in: .flushed)

        // Then it's still expired the next time the cache is opened
        let relaunched = try DataCache(path: cache.path)
        #expect(relaunched.cachedData(for: "b") == nil)
    }

    @Test func expirationSurvivesTheDirectoryBeingRecreated() async throws {
        // Given
        await store(.interval(3600), for: "a", in: .flushed)
        try FileManager.default.removeItem(at: cache.path)

        // When
        await store(.date(.distantPast), for: "b", in: .flushed)

        // Then
        let relaunched = try DataCache(path: cache.path)
        #expect(relaunched.cachedData(for: "b") == nil)
    }

    @Test func cacheWithoutExpiringEntriesDoesNotReadTheAttribute() async throws {
        // Given an entry that has one, in a cache that has no record of it
        cache.storeData(data, for: "a")
        await cache.flush()
        let url = try #require(cache.url(for: "a"))
        var expired: TimeInterval = 0
        #expect(setxattr(url.path, attribute, &expired, MemoryLayout<TimeInterval>.size, 0, 0) == 0)

        // Then
        #expect(cache.cachedData(for: "a") == data)
    }

    @Test func attributeOfTheWrongSizeMeansNoExpiration() async throws {
        // Given
        await store(.interval(3600), for: "b", in: .flushed)
        cache.storeData(data, for: "a")
        await cache.flush()
        let url = try #require(cache.url(for: "a"))
        var value: UInt8 = 1
        #expect(setxattr(url.path, attribute, &value, 1, 0, 0) == 0)

        // Then
        #expect(cache.cachedData(for: "a") == data)
        #expect(cache.expirationDate(for: "a") == nil)
    }

    // MARK: Sweep

    @Test func sweepRemovesExpiredEntries() async {
        // Given a cache way under its size limit
        await store(.date(.distantPast), for: "expired", in: .flushed)
        await store(.interval(3600), for: "valid", in: .flushed)
        await store(.never, for: "never", in: .flushed)
        cache.storeData(data, for: "plain")
        await cache.flush()
        #expect(cache.totalCount == 4)

        // When
        await cache.sweep()

        // Then
        #expect(cache.totalCount == 3)
        #expect(cache.cachedData(for: "expired") == nil)
        #expect(cache.cachedData(for: "valid") == data)
        #expect(cache.cachedData(for: "never") == data)
        #expect(cache.cachedData(for: "plain") == data)
    }

    @Test func sweepCountsWhatIsLeftAfterRemovingExpiredEntries() async throws {
        // Given entries that fit in the limit once the expired one is gone
        let data = Data(repeating: 1, count: 16 * 1024)
        cache.storeData(data, for: "a")
        cache.storeData(data, for: "expired", expiration: .date(.distantPast))
        await cache.flush()
        cache.sizeLimit = cache.totalAllocatedSize - 1

        // When
        await cache.sweep()

        // Then the other entry stays
        #expect(cache.cachedData(for: "a") == data)
        #expect(cache.totalCount == 1)
    }

    @Test func sweepWritesStagedEntriesBeforeLookingForExpiredOnes() async {
        // Given
        cache.storeData(data, for: "a", expiration: .date(.distantPast))

        // When
        await cache.sweep()

        // Then
        #expect(cache.totalCount == 0)
    }
}
