// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: DataCache silently drops the writes whose filename is 251–255 bytes long.
//
// `DataCache.write(_:to:)` (Sources/Nuke/Caching/DataCache.swift:500) writes
// the data to a hidden temporary file named "." + filename + ".tmp" and then
// renames it over the destination. The temporary name is 5 bytes longer than
// the filename the generator produced, so a filename that fits the 255-byte
// NAME_MAX of APFS (the limit the `FilenameGenerator` docs call out) but is
// longer than 250 bytes can't be written: `Data.write(to:)` fails with
// `NSFileWriteInvalidFileNameError` (514), which `perform(_:)` swallows in its
// catch-all ("There is nothing we can do about it", line 479). The change is
// then dropped from the staging area, so the entry is served from memory until
// the flush and is gone right after it – for every write to that key, forever.
//
// This is a regression from #937: the previous non-atomic
// `data.write(to: url)` wrote these filenames without issue. A generator
// that percent-encodes the key and truncates it to 255 bytes, a common
// pattern for readable cache filenames, hits it for every long URL.
//
// Expected: an entry with a valid 252-byte filename is persisted.
// Actual:   nothing is written; after `flush()` the read returns nil and
//           `totalCount` is 0.
@Suite(.timeLimit(.minutes(5)))
struct DataCacheLongFilenameBugRepro {
    @Test func filenameThatFitsTheFileSystemLimitIsPersisted() async throws {
        // GIVEN a generator that produces filenames just under the limit
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataCacheLongFilenameBugRepro-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: path) }
        let cache = try DataCache(path: path, filenameGenerator: { String(repeating: "x", count: 250) + $0 })
        cache.isSweepEnabled = false

        // The filename itself is valid on this file system
        let url = try #require(cache.url(for: "ab"))
        #expect(url.lastPathComponent.utf8.count == 252)
        try Data("probe".utf8).write(to: url)
        try FileManager.default.removeItem(at: url)

        // WHEN
        cache["ab"] = Data("123".utf8)
        await cache.flush()

        // THEN
        #expect(cache["ab"] == Data("123".utf8)) // Actual: nil
        #expect(cache.totalCount == 1) // Actual: 0
    }
}
