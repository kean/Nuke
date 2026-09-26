// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// MARK: - Cache

/// The internal memory cache that backs ``ImageCache``, with explicit costs.
func makeCache(
    costLimit: Int = 1000,
    countLimit: Int = 100,
    entryCostLimit: Double = 1
) -> Cache<String, String> {
    let cache = Cache<String, String>(costLimit: costLimit, countLimit: countLimit)
    cache.conf.entryCostLimit = entryCostLimit
    return cache
}

// MARK: - ImageCache

/// An image without a bitmap costs `1` plus the size of its data, which makes
/// the cost of an entry exact and the same on every platform.
func container(cost: Int) -> ImageContainer {
    precondition(cost >= 1)
    return ImageContainer(image: PlatformImage(), data: Data(count: cost - 1))
}

// MARK: - DataCache

/// A directory in the caches directory, where ``DataCache/init(name:filenameGenerator:)``
/// keeps a cache named after its last path component, that no other test uses.
func makeUniqueCachesDirectoryURL() -> URL {
    URL.cachesDirectory.appendingPathComponent("NukeTests-\(UUID().uuidString)", isDirectory: true)
}

/// The file where ``DataCache`` keeps the date of its last sweep.
func metadataURL(at path: URL) -> URL {
    path.appendingPathComponent(".data-cache-info", isDirectory: false)
}

struct SweepMetadata: Codable {
    var lastSweepDate: Date?
}

func lastSweepDate(at path: URL) -> Date? {
    guard let data = try? Data(contentsOf: metadataURL(at: path)) else {
        return nil
    }
    return try? JSONDecoder().decode(SweepMetadata.self, from: data).lastSweepDate
}

extension DataCache {
    /// The entries on disk. The URLs are standardized to match the ones
    /// ``DataCache/url(for:)`` returns in the temporary directory, which the
    /// file system reports under "/private".
    var contents: [URL] {
        try! FileManager.default.contentsOfDirectory(at: self.path, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .map(\.standardizedFileURL)
    }

    /// Stamps the access dates so that `keys[0]` is the least recently used
    /// entry and the last key is the most recently used one.
    func stampAccessDates(inOrder keys: [String]) throws {
        let now = Date()
        for (index, key) in keys.enumerated() {
            try setAccessDate(now.addingTimeInterval(TimeInterval(index - keys.count - 1) * 100), for: key)
        }
    }

    /// Sets the access date of the file of the entry.
    ///
    /// The modification date goes further back than the access date: APFS
    /// refreshes the access date of a file it reads only while it's older
    /// than the modification date, and the tests need the date to change
    /// only when the cache refreshes it.
    func setAccessDate(_ date: Date, for key: String) throws {
        var url = try #require(self.url(for: key))
        var values = URLResourceValues()
        values.contentModificationDate = date.addingTimeInterval(-10_000)
        values.contentAccessDate = date
        try url.setResourceValues(values)
    }

    /// The access date of the file of the entry.
    func accessDate(for key: String) throws -> Date {
        let url = try #require(self.url(for: key))
        return try #require(url.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate)
    }
}
