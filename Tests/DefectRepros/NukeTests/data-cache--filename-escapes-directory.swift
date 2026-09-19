// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: A generated filename of "" or ".." makes `removeData(for:)` delete the
// whole cache directory or the directory that contains it.
//
// `DataCache.url(for:)` (Sources/Nuke/Caching/DataCache.swift:318-321) appends
// whatever the filename generator returns to `path` without checking that the
// result names a file inside the cache directory. `appendingPathComponent("")`
// returns `path` itself and `appendingPathComponent("..")` its parent, so:
//
// - `containsData(for:)` reports an entry that was never stored (the cache
//   directory exists), and
// - `removeData(for:)` stages a removal that `perform(_:)` carries out with
//   `FileManager.removeItem(at:)` (line 483), which deletes the entire cache
//   directory ("") or its parent (".."). For `DataCache(name:)` the parent is
//   the app's whole Caches directory: URLCache, other libraries' caches, etc.
//
// The default generator guards against the empty key (`key.isEmpty ? nil`),
// but custom generators are a documented extension point, and the ones that
// keep the filenames readable – the identity `{ $0 }` (Nuke's own tests use
// it) or percent-encoding – map "" to "". The pipeline
// produces the empty key on its own: `makeDataCacheKey(for:)` returns "" for
// `ImageRequest(url: nil)`, so `pipeline.cache.removeCachedImage(for:
// ImageRequest(url: nil))` wipes the disk cache.
//
// Expected: a filename that doesn't name a file inside the cache directory
//           ("", ".", "..", or anything that resolves outside of `path`) is
//           treated like `nil` – no entry, nothing to remove.
// Actual:   the reads report a phantom entry, and the removal deletes every
//           entry in the cache, or everything next to the cache directory.
//
// All the directories below are created under a fresh temporary directory,
// so the destructive removals stay inside of it.
@Suite(.timeLimit(.minutes(5)))
struct DataCacheFilenameEscapesDirectoryBugRepro {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("DataCacheFilenameEscapesDirectoryBugRepro-\(UUID().uuidString)", isDirectory: true)

    private func makeCache(filenameGenerator: @escaping DataCache.FilenameGenerator = { $0 }) throws -> DataCache {
        let cache = try DataCache(path: root.appendingPathComponent("cache", isDirectory: true), filenameGenerator: filenameGenerator)
        cache.isSweepEnabled = false
        return cache
    }

    @Test func emptyFilenameDoesNotReferToTheCacheDirectory() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try makeCache()
        cache["a"] = Data("123".utf8)
        await cache.flush()

        // There is no entry for the empty key
        #expect(!cache.containsData(for: "")) // Actual: true

        // WHEN
        cache.removeData(for: "")
        await cache.flush()

        // THEN the other entries are still there
        #expect(cache["a"] == Data("123".utf8)) // Actual: nil, the directory is gone
    }

    @Test func dotDotFilenameDoesNotRemoveTheParentDirectory() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try makeCache()
        let sibling = root.appendingPathComponent("sibling.txt")
        try Data("keep me".utf8).write(to: sibling)
        #expect(!cache.containsData(for: "..")) // Actual: true

        // WHEN
        cache.removeData(for: "..")
        await cache.flush()

        // THEN the files next to the cache directory are untouched
        #expect(FileManager.default.fileExists(atPath: sibling.path)) // Actual: false, `root` is gone
    }

    @Test func removingTheCachedImageForARequestWithoutURLKeepsTheDiskCache() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        // A generator that keeps the filenames readable
        let cache = try makeCache(filenameGenerator: { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) })
        let pipeline = ImagePipeline {
            $0.dataCache = cache
            $0.dataLoader = MockDataLoader()
        }
        let request = ImageRequest(url: URL(string: "https://example.com/image.jpeg"))
        pipeline.cache.storeCachedData(Data("123".utf8), for: request)
        await cache.flush()
        #expect(pipeline.cache.cachedData(for: request) == Data("123".utf8)) // Passes
        #expect(cache.totalCount == 1) // Passes

        // WHEN
        pipeline.cache.removeCachedImage(for: ImageRequest(url: nil))
        await cache.flush()

        // THEN
        #expect(pipeline.cache.cachedData(for: request) == Data("123".utf8)) // Actual: nil
    }
}
