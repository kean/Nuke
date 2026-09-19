// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: `DataCache(name: "")` adopts the app's Caches directory itself instead
// of creating a directory of its own in it.
//
// `DataCache.init(name:filenameGenerator:)` (Sources/Nuke/Caching/DataCache.swift:150-152)
// passes `URL.cachesDirectory.appendingPathComponent(name, isDirectory: true)`
// to `init(path:)`. For an empty name, `appendingPathComponent("")` returns
// the Caches directory unchanged (and "." / ".." resolve to it or to
// `Library`). The docs say "The cache creates a directory with the given
// `name` in a `.cachesDirectory`", but here it creates none and treats every
// file and directory of the app's caches as its own:
//
// - `removeAll()` runs `FileManager.removeItem(at: path)` (line 517) – it
//   deletes the entire Caches directory, including URLCache's storage and the
//   caches of every other library in the app;
// - the LRU sweep ranks and deletes the top-level items of the Caches
//   directory once the files in it exceed `sizeLimit`;
// - `totalCount` counts the unrelated directories as entries.
//
// An empty name is easy to end up with by accident, e.g.
// `DataCache(name: Bundle.main.bundleIdentifier ?? "")` in a test host or an
// extension, or a name read from a configuration.
//
// Expected: the initializer rejects a name that doesn't name a subdirectory
//           ("", ".", "..", or containing a path separator that leaves the
//           Caches directory) by throwing, or the cache gets a directory of
//           its own.
// Actual:   the initializer succeeds and `path` is the Caches directory.
//
// The repro never calls a destructive method on the cache, and it disables
// the sweep and releases the cache before the first sweep could run.
@Suite(.timeLimit(.minutes(5)))
struct DataCacheEmptyNameBugRepro {
    @Test func emptyNameDoesNotTakeOverTheCachesDirectory() {
        guard let cache = try? DataCache(name: "") else {
            return // Rejecting the name is an acceptable fix
        }
        cache.isSweepEnabled = false

        #expect(cache.path.standardizedFileURL != URL.cachesDirectory.standardizedFileURL) // Actual: equal
    }
}
