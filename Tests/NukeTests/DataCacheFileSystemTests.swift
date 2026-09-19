// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

private let blob = Data("123".utf8)
private let otherBlob = Data("456".utf8)

/// A directory in the temporary folder that no other test uses.
private func makeUniqueDirectoryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("DataCacheFileSystemTests-\(UUID().uuidString)", isDirectory: true)
}

/// The hidden file ``DataCache`` writes an entry to before renaming it over
/// the destination.
private func temporaryFileURL(for url: URL) -> URL {
    url.deletingLastPathComponent()
        .appendingPathComponent("." + url.lastPathComponent + ".tmp", isDirectory: false)
}

/// Everything in the cache directory, including the hidden files that the
/// inspection API skips.
private func allFilenames(in cache: DataCache) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: cache.path.path)
}

/// How ``DataCache`` behaves on disk: the directory it manages, the files it
/// writes and the file system errors it runs into.
@Suite(.timeLimit(.minutes(5)))
final class DataCacheFileSystemTests {
    private let cache: DataCache

    init() throws {
        cache = try DataCache(path: makeUniqueDirectoryURL())
        // The tests check the exact contents of the directory, which the
        // scheduled sweep would otherwise be free to change under them.
        cache.isSweepEnabled = false
    }

    deinit {
        cache.suspendIO()
        try? FileManager.default.removeItem(at: cache.path)
    }

    // MARK: Init

    @Test func initWithNameCreatesTheDirectoryInTheCachesDirectory() throws {
        // WHEN
        let name = "DataCacheFileSystemTests-\(UUID().uuidString)"
        let cache = try DataCache(name: name)
        defer { try? FileManager.default.removeItem(at: cache.path) }
        cache.isSweepEnabled = false

        // THEN
        #expect(cache.path.deletingLastPathComponent().standardizedFileURL == URL.cachesDirectory.standardizedFileURL)
        #expect(cache.path.lastPathComponent == name)
        #expect(FileManager.default.fileExists(atPath: cache.path.path))
    }

    @Test func initWithPathCreatesTheIntermediateDirectories() throws {
        // GIVEN a path several levels below a directory that doesn't exist yet
        let root = makeUniqueDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("a/b/c", isDirectory: true)

        // WHEN
        let cache = try DataCache(path: path)
        cache.isSweepEnabled = false

        // THEN
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(cache.path == path)
    }

    @Test func initThrowsWhenThePathIsARegularFile() throws {
        // GIVEN a file where the directory is supposed to go
        let path = makeUniqueDirectoryURL()
        defer { try? FileManager.default.removeItem(at: path) }
        try blob.write(to: path)

        // WHEN/THEN the cache refuses to take it over instead of failing
        // every write later on
        #expect(throws: (any Error).self) {
            _ = try DataCache(path: path)
        }
        #expect(try Data(contentsOf: path) == blob)
    }

    // MARK: Values

    @Test func emptyDataIsStoredAsAnEntry() async {
        // WHEN
        cache["key"] = Data()
        await cache.flush()

        // THEN it reads back as empty data, not as a miss
        #expect(cache.cachedData(for: "key") == Data())
        #expect(cache.containsData(for: "key"))
        #expect(cache.totalCount == 1)
        #expect(cache.totalSize == 0)
    }

    // MARK: Keys

    @Test func veryLongKeysAreStoredUsingTheDefaultFilenameGenerator() async throws {
        // GIVEN a key far over the file system limit for a filename
        let key = "https://example.com/" + String(repeating: "a", count: 10_000)

        // WHEN
        cache[key] = blob
        await cache.flush()

        // THEN the hash keeps the filename short
        let filename = try #require(cache.filename(for: key))
        #expect(filename.count == 40)
        #expect(filename.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(cache.cachedData(for: key) == blob)
        #expect(cache.contents.map(\.lastPathComponent) == [cache.filename(for: key)])
    }

    /// The default file system on macOS is case-insensitive, so the keys that
    /// differ only in case would share a file if they were used as is.
    @Test func keysThatDifferOnlyInCaseAreStoredSeparately() async {
        // WHEN
        cache["https://example.com/image.png"] = blob
        cache["https://example.com/IMAGE.png"] = otherBlob
        await cache.flush()

        // THEN
        #expect(cache.totalCount == 2)
        #expect(cache["https://example.com/image.png"] == blob)
        #expect(cache["https://example.com/IMAGE.png"] == otherBlob)
    }

    /// The atomic write renames the file using its file system representation,
    /// which must survive the characters that need escaping in a URL.
    @Test func specialCharactersInTheFilenameAndThePathRoundTrip() async throws {
        // GIVEN a directory and filenames that need escaping in a URL
        let root = makeUniqueDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try DataCache(
            path: root.appendingPathComponent("Data Cache ✓ #1", isDirectory: true),
            filenameGenerator: { $0 }
        )
        cache.isSweepEnabled = false
        let keys = ["key with spaces", "ключ", "画像🖼️", "percent%20plus+", "colon:semi;comma,", "quote'double\"", "#hash?query&"]

        // WHEN
        for (index, key) in keys.enumerated() {
            cache[key] = Data("\(index)".utf8)
        }
        await cache.flush()

        // THEN every entry is on disk under its own name
        #expect(Set(try allFilenames(in: cache)) == Set(keys))
        for (index, key) in keys.enumerated() {
            #expect(cache[key] == Data("\(index)".utf8), "\(key)")
        }
    }

    /// The filename generator is the only thing that tells the entries apart.
    @Test func keysThatCollideInTheFilenameGeneratorShareAnEntry() async throws {
        // GIVEN
        let root = makeUniqueDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try DataCache(path: root, filenameGenerator: { _ in "shared" })
        cache.isSweepEnabled = false

        // WHEN
        cache["a"] = blob
        await cache.flush()

        // THEN the other key reads the same file
        #expect(cache.totalCount == 1)
        #expect(cache["b"] == blob)

        // WHEN one of them is removed
        cache["b"] = nil
        await cache.flush()

        // THEN it takes the other one with it
        #expect(cache["a"] == nil)
        #expect(cache.totalCount == 0)
    }

    @Test func changesForKeysWithoutAFilenameAreDroppedOnFlush() async throws {
        // GIVEN a generator that can't produce a filename for some keys
        let root = makeUniqueDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try DataCache(path: root, filenameGenerator: { $0.hasPrefix("skip") ? nil : $0 })
        cache.isSweepEnabled = false

        // WHEN
        cache["skip-1"] = blob
        cache["keep"] = otherBlob
        await cache.flush()

        // THEN the change doesn't linger in the staging area after it has
        // nowhere to go, and it doesn't take the other changes down with it
        #expect(cache["skip-1"] == nil)
        #expect(!cache.containsData(for: "skip-1"))
        #expect(cache.url(for: "skip-1") == nil)
        #expect(cache["keep"] == otherBlob)
        #expect(try allFilenames(in: cache) == ["keep"])
    }

    // MARK: Write Errors

    /// Covers the case where the rename fails after the temporary file is
    /// written: it must not leak the temporary file or stop the batch.
    @Test func failedRenameCleansUpTheTemporaryFileAndDoesNotStopTheOtherWrites() async throws {
        // GIVEN a directory in place of the file one of the entries goes to
        let blockedURL = try #require(cache.url(for: "blocked"))
        try FileManager.default.createDirectory(at: blockedURL, withIntermediateDirectories: false)

        // WHEN
        cache["blocked"] = blob
        cache["other"] = otherBlob
        await cache.flush()

        // THEN the write that can't complete leaves nothing behind
        #expect(!FileManager.default.fileExists(atPath: temporaryFileURL(for: blockedURL).path))
        #expect(try !allFilenames(in: cache).contains { $0.hasSuffix(".tmp") })
        #expect(cache["blocked"] == nil)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: blockedURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        // AND the other change in the same batch still reaches the disk
        #expect(cache["other"] == otherBlob)
        let otherURL = try #require(cache.url(for: "other"))
        #expect(try Data(contentsOf: otherURL) == otherBlob)

        // AND the directory in the way has no size to add to the totals
        #expect(cache.totalSize == otherBlob.count)
        let otherAllocatedSize = try otherURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
        #expect(cache.totalAllocatedSize == otherAllocatedSize)
    }

    @Test func aTemporaryFileLeftBehindIsReclaimedByTheNextWriteToTheKey() async throws {
        // GIVEN the temporary file of a write that never completed, e.g.
        // because the process was killed in the middle of it
        let url = try #require(cache.url(for: "key"))
        let tempURL = temporaryFileURL(for: url)
        try Data(repeating: 9, count: 1024).write(to: tempURL)

        // THEN it isn't mistaken for an entry
        #expect(cache.totalCount == 0)
        #expect(cache.totalSize == 0)
        #expect(cache["key"] == nil)

        // WHEN the key is written again
        cache["key"] = blob
        await cache.flush()

        // THEN the leftover is gone and the entry has the new data
        #expect(!FileManager.default.fileExists(atPath: tempURL.path))
        #expect(try Data(contentsOf: url) == blob)
        #expect(cache.totalCount == 1)
    }

    @Test func removeAllReclaimsTheTemporaryFilesLeftBehind() async throws {
        // GIVEN an entry and a temporary file that isn't going to be reclaimed
        // by a write because its key is never written again
        cache["key"] = blob
        await cache.flush()
        let tempURL = temporaryFileURL(for: try #require(cache.url(for: "orphan")))
        try blob.write(to: tempURL)

        // WHEN
        cache.removeAll()
        await cache.flush()

        // THEN
        #expect(try allFilenames(in: cache).isEmpty)
        #expect(cache["key"] == nil)
    }

    // MARK: Read Errors

    @Test(.enabled(if: getuid() != 0, "root reads the file regardless of its permissions"))
    func unreadableFileIsAMissThatDoesNotRefreshTheAccessDate() async throws {
        // GIVEN an entry that the process isn't allowed to read
        cache["key"] = blob
        await cache.flush()
        let url = try #require(cache.url(for: "key"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        // WHEN
        let data = cache.cachedData(for: "key")
        await cache.flush()

        // THEN
        #expect(data == nil)
        #expect(cache.accessDateUpdateCount == 0)
        #expect(cache.containsData(for: "key")) // Checks the existence without reading it
    }

    @Test func missDoesNotScheduleAnAccessDateUpdate() async {
        // WHEN reading a key that has no entry on disk
        #expect(cache.cachedData(for: "missing") == nil)
        await cache.flush()

        // THEN there is no file to touch, so no work is queued for it
        #expect(cache.accessDateUpdateCount == 0)
    }

    // MARK: Directory Removed Externally

    @Test func inspectionReportsAnEmptyCacheWhenTheDirectoryIsGone() async throws {
        // GIVEN
        cache["key"] = blob
        await cache.flush()

        // WHEN something else removes the directory
        try FileManager.default.removeItem(at: cache.path)

        // THEN
        #expect(cache.totalCount == 0)
        #expect(cache.totalSize == 0)
        #expect(cache.totalAllocatedSize == 0)
        #expect(cache["key"] == nil)
        #expect(!cache.containsData(for: "key"))
    }

    @Test func sweepWithTheDirectoryGoneLeavesTheCacheUsable() async throws {
        // GIVEN
        cache["key"] = blob
        await cache.flush()
        try FileManager.default.removeItem(at: cache.path)

        // WHEN
        await cache.sweep()

        // THEN the cache is still usable
        cache["key"] = otherBlob
        await cache.flush()
        #expect(cache["key"] == otherBlob)
        #expect(cache.totalCount == 1)
    }

    @Test func removeAllRecreatesTheDirectoryWhenItIsGone() async throws {
        // GIVEN
        try FileManager.default.removeItem(at: cache.path)

        // WHEN
        cache.removeAll()
        await cache.flush()

        // THEN
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: cache.path.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}
