// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

/// An LRU disk cache that stores data in separate files.
///
/// ``DataCache`` uses LRU cleanup policy (least recently used items are removed
/// first). The elements stored in the cache are automatically discarded if
/// the size limit is reached. The sweeps are performed periodically.
///
/// DataCache always writes and removes data asynchronously. It also allows for
/// reading and writing data in parallel. It is implemented using a staging
/// area which stores changes until they are flushed to disk:
///
/// ```swift
/// // Schedules data to be written asynchronously and returns immediately
/// cache[key] = data
///
/// // The data is returned from the staging area
/// let data = cache[key]
///
/// // Schedules data to be removed asynchronously and returns immediately
/// cache[key] = nil
///
/// // Data is nil
/// let data = cache[key]
/// ```
///
/// - important: It's possible to have more than one instance of ``DataCache`` with
/// the same path but it is not recommended.
public final class DataCache: DataCaching, Sendable {
    /// The path for the directory managed by the cache.
    public let path: URL

    /// Size limit in bytes. `150 MB` by default.
    ///
    /// Changes to the size limit will take effect when the next LRU sweep is run.
    public var sizeLimit: Int {
        get { state.withLock { $0.sizeLimit } }
        set { state.withLock { $0.sizeLimit = newValue } }
    }

    /// The time interval between cache sweeps. The default value is 30 minutes.
    public var sweepInterval: TimeInterval {
        get { state.withLock { $0.sweepInterval } }
        set { state.withLock { $0.sweepInterval = newValue } }
    }

    /// If `false`, the automatic LRU sweep is disabled. The default value is `true`.
    public var isSweepEnabled: Bool {
        get { state.withLock { $0.isSweepEnabled } }
        set { state.withLock { $0.isSweepEnabled = newValue } }
    }

    /// When performing a sweep, the cache will remove entries until the size of
    /// the remaining items is lower than or equal to `sizeLimit * trimRatio`. `0.7`
    /// by default.
    var trimRatio: Double {
        get { state.withLock { $0.trimRatio } }
        set { state.withLock { $0.trimRatio = newValue } }
    }

    /// The delay between the moment a change is staged and the moment it is
    /// written to disk. `1` second by default.
    var flushInterval: Duration {
        get { state.withLock { $0.flushInterval } }
        set { state.withLock { $0.flushInterval = newValue } }
    }

    /// A function that generates a filename for the given key. A good candidate
    /// is a hash function with low collision probability, such as SHA1.
    ///
    /// The reason filenames need to be generated is that filesystems have a
    /// size limit for filenames (e.g. 255 UTF-8 characters in APFS) and do not
    /// allow certain characters.
    public typealias FilenameGenerator = @Sendable (_ key: String) -> String?

    /// All of the mutable state, guarded by a single lock.
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Serializes the changes applied to the filesystem. Reads never acquire it,
    /// so they continue to run in parallel with the writes and with each other.
    private let ioLock = NSLock()

    private let filenameGenerator: FilenameGenerator
    private let sweepDelay: Duration
    private let onSweepCompleted: (@Sendable () -> Void)?

    private struct State {
        var staging = Staging()
        var isFlushScheduled = false
        var sizeLimit = 1024 * 1024 * 150
        var sweepInterval: TimeInterval = 1800
        var isSweepEnabled = true
        var trimRatio = 0.7
        var flushInterval = Duration.seconds(1)
    }

    private struct Metadata: Codable {
        var lastSweepDate: Date?
    }

    // MARK: Initializers

    /// Creates a cache instance with a given `name`. The cache creates a directory
    /// with the given `name` in a `.cachesDirectory` in `.userDomainMask`.
    /// - parameter name: The name of the directory in which the cache is stored.
    /// - parameter filenameGenerator: Generates a filename for the given URL.
    /// The default implementation generates a filename using SHA1 hash function.
    public convenience init(name: String, filenameGenerator: @escaping FilenameGenerator = DataCache.filename(for:)) throws {
        try self.init(path: URL.cachesDirectory.appendingPathComponent(name, isDirectory: true), filenameGenerator: filenameGenerator)
    }

    /// Creates a cache instance with a given path.
    /// - parameter path: The path of the directory in which the cache is stored.
    /// - parameter filenameGenerator: Generates a filename for the given URL.
    /// The default implementation generates a filename using SHA1 hash function.
    public convenience init(path: URL, filenameGenerator: @escaping FilenameGenerator = DataCache.filename(for:)) throws {
        try self.init(path: path, filenameGenerator: filenameGenerator, sweepDelay: .seconds(5), onSweepCompleted: nil)
    }

    convenience init(
        name: String,
        filenameGenerator: @escaping FilenameGenerator = DataCache.filename(for:),
        sweepDelay: Duration,
        onSweepCompleted: @escaping @Sendable () -> Void
    ) throws {
        try self.init(path: URL.cachesDirectory.appendingPathComponent(name, isDirectory: true), filenameGenerator: filenameGenerator, sweepDelay: sweepDelay, onSweepCompleted: onSweepCompleted)
    }

    private init(
        path: URL,
        filenameGenerator: @escaping FilenameGenerator,
        sweepDelay: Duration,
        onSweepCompleted: (@Sendable () -> Void)?
    ) throws {
        self.path = path
        self.filenameGenerator = filenameGenerator
        self.sweepDelay = sweepDelay
        self.onSweepCompleted = onSweepCompleted
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)
        scheduleSweep()
    }

    /// A ``FilenameGenerator`` implementation that uses SHA1 to generate a
    /// filename from the given key.
    public static func filename(for key: String) -> String? {
        key.isEmpty ? nil : key.sha1
    }

    // MARK: DataCaching

    /// Retrieves data for the given key.
    public func cachedData(for key: String) -> Data? {
        if let change = change(for: key) {
            switch change { // Change wasn't flushed to disk yet
            case let .add(data):
                return data
            case .remove:
                return nil
            }
        }
        guard var url = url(for: key), let data = try? Data(contentsOf: url) else {
            return nil
        }
        var values = URLResourceValues()
        values.contentAccessDate = Date()
        try? url.setResourceValues(values)
        return data
    }

    /// Returns `true` if the cache contains the data for the given key.
    public func containsData(for key: String) -> Bool {
        if let change = change(for: key) {
            switch change { // Change wasn't flushed to disk yet
            case .add:
                return true
            case .remove:
                return false
            }
        }
        guard let url = url(for: key) else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func change(for key: String) -> Staging.ChangeType? {
        state.withLock { $0.staging.change(for: key) }
    }

    /// Stores data for the given key. The method returns instantly and the data
    /// is written asynchronously.
    public func storeData(_ data: Data, for key: String) {
        stage { $0.add(data: data, for: key) }
    }

    /// Removes data for the given key. The method returns instantly, the data
    /// is removed asynchronously.
    public func removeData(for key: String) {
        stage { $0.removeData(for: key) }
    }

    /// Removes all items. The method returns instantly, the data is removed
    /// asynchronously.
    public func removeAll() {
        stage { $0.removeAll() }
    }

    /// Registers a change and schedules a flush unless one is already scheduled.
    private func stage(_ change: @Sendable (inout Staging) -> Void) {
        let flushInterval: Duration? = state.withLock {
            change(&$0.staging)
            guard !$0.isFlushScheduled else { return nil }
            $0.isFlushScheduled = true
            return $0.flushInterval
        }
        guard let flushInterval else { return }
        // `self` is captured strongly on purpose: the staged data has to reach
        // the disk even if the client releases the cache in the meantime.
        Task.detached(priority: .utility) { [self] in
            try? await Task.sleep(for: flushInterval)
            state.withLock { $0.isFlushScheduled = false }
            flush()
        }
    }

    /// Accesses the data associated with the given key for reading and writing.
    ///
    /// When you assign data for a key that already exists, the cache overwrites
    /// the existing entry. Reads and writes are backed by a staging area, so
    /// they can occur in parallel without blocking. All writes are flushed to
    /// disk asynchronously.
    public subscript(key: String) -> Data? {
        get {
            cachedData(for: key)
        }
        set {
            if let data = newValue {
                storeData(data, for: key)
            } else {
                removeData(for: key)
            }
        }
    }

    // MARK: Managing URLs

    /// Uses the filename generator that the cache was initialized with to
    /// generate and return a filename for the given key.
    public func filename(for key: String) -> String? {
        filenameGenerator(key)
    }

    /// Returns `url` for the given cache key.
    public func url(for key: String) -> URL? {
        guard let filename = self.filename(for: key) else { return nil }
        return self.path.appendingPathComponent(filename, isDirectory: false)
    }

    // MARK: Flush Changes

    /// Synchronously waits on the caller's thread until all outstanding disk I/O
    /// operations are finished.
    public func flush() {
        ioLock.withLock {
            let staging = state.withLock { $0.staging }
            guard !staging.isEmpty else { return }
            autoreleasepool {
                if staging.changeRemoveAll != nil {
                    performRemoveAll()
                }
                for change in staging.changes.values {
                    perform(change)
                }
            }
            state.withLock { $0.staging.flushed(staging) }
        }
    }

    /// Synchronously waits on the caller's thread until all outstanding disk I/O
    /// operations for the given key are finished.
    public func flush(for key: String) {
        ioLock.withLock {
            guard let change = state.withLock({ $0.staging.changes[key] }) else { return }
            perform(change)
            state.withLock { $0.staging.flushed(change) }
        }
    }

    /// Suspends the disk I/O for the duration of the closure (testing only).
    func withSuspendedIO(_ closure: () -> Void) {
        ioLock.withLock(closure)
    }

    // MARK: - I/O

    private func perform(_ change: Staging.Change) {
        guard let url = url(for: change.key) else {
            return
        }
        switch change.type {
        case let .add(data):
            do {
                try data.write(to: url)
            } catch let error as NSError where error.code == CocoaError.fileNoSuchFile.rawValue && error.domain == CocoaError.errorDomain {
                createDirectory() // The directory is gone, re-create it and try again
                try? data.write(to: url)
            } catch {
                // There is nothing we can do about it
            }
        case .remove:
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func performRemoveAll() {
        try? FileManager.default.removeItem(at: path)
        createDirectory()
    }

    private func createDirectory() {
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)
    }

    // MARK: Sweep

    private func scheduleSweep() {
        let sweepDelay = self.sweepDelay
        // Add a bit of a delay to free the resources during launch.
        //
        // - important: `.utility`, not `.background`: `Task.sleep` at background
        // priority is subject to timer coalescing and can be delayed by seconds.
        Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: sweepDelay)
            guard let self, isSweepEnabled, isSweepNeeded() else { return }
            sweep()
            updateMetadata { $0.lastSweepDate = Date() }
            onSweepCompleted?()
        }
    }

    private func isSweepNeeded() -> Bool {
        guard let lastSweepDate = getMetadata().lastSweepDate else {
            return true
        }
        return Date().timeIntervalSince(lastSweepDate) >= sweepInterval
    }

    /// Synchronously performs a cache sweep and removes the least recently used
    /// items that no longer fit in the cache.
    public func sweep() {
        ioLock.withLock {
            var items = contents(keys: [.contentAccessDateKey, .totalFileAllocatedSizeKey])
            var size = items.reduce(0) { $0 + ($1.meta.totalFileAllocatedSize ?? 0) }
            let (sizeLimit, trimRatio) = state.withLock { ($0.sizeLimit, $0.trimRatio) }
            guard size > sizeLimit else {
                return // All good, no need to perform any work.
            }
            let targetSizeLimit = Int(Double(sizeLimit) * trimRatio)

            // Most recently accessed items first
            let past = Date.distantPast
            items.sort { // Sort in place
                ($0.meta.contentAccessDate ?? past) > ($1.meta.contentAccessDate ?? past)
            }

            // Remove the items until it satisfies both size and count limits.
            while size > targetSizeLimit, let item = items.popLast() {
                size -= (item.meta.totalFileAllocatedSize ?? 0)
                try? FileManager.default.removeItem(at: item.url)
            }
        }
    }

    // MARK: Contents

    struct Entry {
        let url: URL
        let meta: URLResourceValues
    }

    func contents(keys: [URLResourceKey] = []) -> [Entry] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: keys, options: .skipsHiddenFiles) else {
            return []
        }
        let keys = Set(keys)
        return urls.compactMap {
            guard let meta = try? $0.resourceValues(forKeys: keys) else {
                return nil
            }
            return Entry(url: $0, meta: meta)
        }
    }

    // MARK: Metadata

    private func getMetadata() -> Metadata {
        if let data = try? Data(contentsOf: metadataFileURL),
           let metadata = try? JSONDecoder().decode(Metadata.self, from: data) {
            return metadata
        }
        return Metadata()
    }

    private func updateMetadata(_ closure: (inout Metadata) -> Void) {
        var metadata = getMetadata()
        closure(&metadata)
        try? JSONEncoder().encode(metadata).write(to: metadataFileURL)
    }

    private var metadataFileURL: URL {
        path.appendingPathComponent(".data-cache-info", isDirectory: false)
    }

    // MARK: Inspection

    /// The total number of items in the cache.
    ///
    /// - important: Requires disk IO, avoid using from the main thread.
    public var totalCount: Int {
        contents().count
    }

    /// The total file size of items written on disk.
    ///
    /// Uses `URLResourceKey.fileSizeKey` to calculate the size of each entry.
    /// The total allocated size (see ``totalAllocatedSize``) on disk might
    /// actually be bigger.
    ///
    /// - important: Requires disk IO, avoid using from the main thread.
    public var totalSize: Int {
        contents(keys: [.fileSizeKey]).reduce(0) {
            $0 + ($1.meta.fileSize ?? 0)
        }
    }

    /// The total file allocated size of all the items written on disk.
    ///
    /// Uses `URLResourceKey.totalFileAllocatedSizeKey`.
    ///
    /// - important: Requires disk IO, avoid using from the main thread.
    public var totalAllocatedSize: Int {
        contents(keys: [.totalFileAllocatedSizeKey]).reduce(0) {
            $0 + ($1.meta.totalFileAllocatedSize ?? 0)
        }
    }
}

// MARK: - Staging

/// DataCache allows for parallel reads and writes. This is made possible by
/// DataCacheStaging.
///
/// For example, when the data is added in cache, it is first added to staging
/// and is removed from staging only after data is written to disk. Removal works
/// the same way.
private struct Staging {
    private(set) var changes = [String: Change]()
    private(set) var changeRemoveAll: ChangeRemoveAll?
    private var nextChangeId = 0

    var isEmpty: Bool {
        changes.isEmpty && changeRemoveAll == nil
    }

    struct ChangeRemoveAll {
        let id: Int
    }

    struct Change {
        let key: String
        let id: Int
        let type: ChangeType
    }

    enum ChangeType {
        case add(Data)
        case remove
    }

    // MARK: Changes

    func change(for key: String) -> ChangeType? {
        if let change = changes[key] {
            return change.type
        }
        if changeRemoveAll != nil {
            return .remove
        }
        return nil
    }

    // MARK: Register Changes

    mutating func add(data: Data, for key: String) {
        nextChangeId += 1
        changes[key] = Change(key: key, id: nextChangeId, type: .add(data))
    }

    mutating func removeData(for key: String) {
        nextChangeId += 1
        changes[key] = Change(key: key, id: nextChangeId, type: .remove)
    }

    mutating func removeAll() {
        nextChangeId += 1
        changeRemoveAll = ChangeRemoveAll(id: nextChangeId)
        changes.removeAll()
    }

    // MARK: Flush Changes

    mutating func flushed(_ staging: Staging) {
        for change in staging.changes.values {
            flushed(change)
        }
        if let change = staging.changeRemoveAll {
            flushed(change)
        }
    }

    mutating func flushed(_ change: Change) {
        if let index = changes.index(forKey: change.key),
           changes[index].value.id == change.id {
            changes.remove(at: index)
        }
    }

    mutating func flushed(_ change: ChangeRemoveAll) {
        if changeRemoveAll?.id == change.id {
            changeRemoveAll = nil
        }
    }
}
