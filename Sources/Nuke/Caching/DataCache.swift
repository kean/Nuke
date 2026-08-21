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

    /// A function that generates a filename for the given key. A good candidate
    /// is a hash function with low collision probability, such as SHA1.
    ///
    /// The reason filenames need to be generated is that filesystems have a
    /// size limit for filenames (e.g. 255 UTF-8 characters in APFS) and do not
    /// allow certain characters.
    public typealias FilenameGenerator = @Sendable (_ key: String) -> String?

    /// All of the mutable state, guarded by a single lock.
    private let state = OSAllocatedUnfairLock(initialState: State())

    private let filenameGenerator: FilenameGenerator
    private let sweepDelay: Duration
    private let onSweepCompleted: (@Sendable () -> Void)?

    /// The queue that all of the blocking disk I/O runs on.
    ///
    /// The cache is driven by Swift concurrency, but the file operations
    /// themselves are synchronous and can block for a long time. Performing
    /// them directly in a task would occupy one of the few threads in the
    /// cooperative pool for the entire duration of a write, so the writer hops
    /// onto a dispatch queue instead – blocking work is what GCD threads are
    /// for. The queue is serial, so the disk operations never overlap.
    ///
    /// - note: `.default`, not `.utility`. A block submitted with `async` never
    /// gets its priority escalated, so at `.utility` the caller of ``flush()``
    /// ends up waiting on throttled I/O. The previous implementation could
    /// afford `.utility` because it used `sync`, which donates the QoS.
    ///
    /// - note: When the deployment target reaches iOS 17, replace the queue
    /// with an actor that uses `DispatchSerialQueue` as its `SerialExecutor`.
    /// The I/O keeps running on a GCD thread, but without the manual hops.
    private let ioQueue = DispatchQueue(label: "com.github.kean.Nuke.DataCache.io", qos: .default)

    private struct State {
        var staging = Staging()
        /// The single task that drives the disk I/O, or `nil` when the cache
        /// is idle. At most one writer exists at any time: it drains the
        /// pending work in a loop and exits when there is none left.
        ///
        /// - invariant: If there is pending work, the writer exists, unless
        /// the I/O is suspended (testing only).
        var writer: Task<Void, Never>?
        /// Prevents the writer from starting (testing only).
        var isWriterSuspended = false
        /// A sweep was scheduled on launch and runs only if one hasn't been
        /// performed recently (see ``DataCache/sweepInterval``).
        var isSweepScheduled = false
        /// A sweep was explicitly requested with ``DataCache/sweep()``.
        var isSweepRequested = false
        var sizeLimit = 1024 * 1024 * 150
        var sweepInterval: TimeInterval = 1800
        var isSweepEnabled = true
        var trimRatio = 0.7

        var hasPendingWork: Bool {
            !staging.isEmpty || isSweepScheduled || isSweepRequested
        }
    }

    private enum WriterJob {
        case flush(Staging)
        case sweep(isScheduled: Bool)
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

    private func stage(_ change: @Sendable (inout Staging) -> Void) {
        scheduleWork { change(&$0.staging) }
    }

    /// Registers pending work and starts the writer unless one is already running.
    private func scheduleWork(_ change: @Sendable (inout State) -> Void) {
        state.withLock {
            change(&$0)
            guard $0.writer == nil, !$0.isWriterSuspended, $0.hasPendingWork else { return }
            $0.writer = makeWriter()
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

    /// Waits until all outstanding disk operations — the pending writes,
    /// removals, and sweeps — are finished.
    public func flush() async {
        await drain { _ in }
    }

    /// Performs a cache sweep, removing the least recently used items that no
    /// longer fit in the cache, and waits for it to finish.
    public func sweep() async {
        await drain { $0.isSweepRequested = true }
    }

    /// Registers the pending work and waits until the writer drains all of it.
    private func drain(_ change: @Sendable (inout State) -> Void) async {
        scheduleWork(change)
        while true {
            if let writer = state.withLock({ $0.writer }) {
                await writer.value
                continue // The exited writer may have left new work behind
            }
            guard state.withLock({ $0.hasPendingWork }) else {
                return
            }
            // The I/O is suspended (testing only) — wait until it is resumed.
            await Task.yield()
        }
    }

    /// Suspends the disk I/O for the duration of the closure (testing only).
    ///
    /// - important: Assumes the writer is idle when the closure is invoked. The
    /// writer never starts while the I/O is suspended.
    func withSuspendedIO(_ closure: () -> Void) {
        suspendIO()
        closure()
        resumeIO()
    }

    /// Prevents the writer from starting until ``resumeIO()`` (testing only).
    func suspendIO() {
        state.withLock { $0.isWriterSuspended = true }
    }

    /// Lifts the ``suspendIO()`` suspension and restarts the writer if any
    /// work accumulated in the meantime (testing only).
    func resumeIO() {
        state.withLock {
            $0.isWriterSuspended = false
            guard $0.writer == nil, $0.hasPendingWork else { return }
            $0.writer = makeWriter()
        }
    }

    // MARK: - Writer

    /// Creates the single task that drives all of the disk mutations. The task
    /// drains the pending work in a loop and exits when there is none left. The
    /// work staged while a write is in progress is picked up by the next
    /// iteration, so the writes batch up automatically under load.
    private func makeWriter() -> Task<Void, Never> {
        // `self` is captured strongly on purpose: the staged data has to reach
        // the disk even if the client releases the cache in the meantime. The
        // task exits once the work is drained, releasing the cache with it.
        Task.detached(priority: .utility) { [self] in
            await performIO {
                while let job = self.nextJob() {
                    self.perform(job)
                }
            }
        }
    }

    /// Runs the blocking work on ``ioQueue`` without occupying a thread from
    /// the cooperative pool while it executes.
    ///
    /// There is one continuation per writer, not per file, so its cost is
    /// negligible next to the disk operations it wraps.
    private func performIO(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            ioQueue.async {
                work()
                continuation.resume()
            }
        }
    }

    private func perform(_ job: WriterJob) {
        switch job {
        case let .flush(staging):
            performChanges(staging)
        case let .sweep(isScheduled):
            if isScheduled {
                guard isSweepNeeded() else { return }
                performSweep()
                updateMetadata { $0.lastSweepDate = Date() }
                onSweepCompleted?()
            } else {
                performSweep()
            }
        }
    }

    private func nextJob() -> WriterJob? {
        state.withLock {
            guard !$0.isWriterSuspended else {
                // Exit and leave the pending work behind: it is picked up when
                // the writer is restarted by `resumeIO()`.
                $0.writer = nil
                return nil
            }
            if !$0.staging.isEmpty {
                return .flush($0.staging)
            }
            if $0.isSweepRequested {
                $0.isSweepRequested = false
                return .sweep(isScheduled: false)
            }
            if $0.isSweepScheduled {
                $0.isSweepScheduled = false
                return .sweep(isScheduled: true)
            }
            $0.writer = nil
            return nil
        }
    }

    // MARK: - I/O

    private func performChanges(_ staging: Staging) {
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
            guard let self, isSweepEnabled else { return }
            scheduleWork { $0.isSweepScheduled = true }
        }
    }

    private func isSweepNeeded() -> Bool {
        guard let lastSweepDate = getMetadata().lastSweepDate else {
            return true
        }
        return Date().timeIntervalSince(lastSweepDate) >= sweepInterval
    }

    private func performSweep() {
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
