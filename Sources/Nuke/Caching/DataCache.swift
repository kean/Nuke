// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

/// An LRU disk cache that stores data in separate files.
///
/// ``DataCache`` uses LRU cleanup policy (least recently used items are removed
/// first). The elements stored in the cache are automatically discarded if
/// the size limit is reached. The sweeps are performed periodically for as
/// long as the cache is alive, see ``DataCache/sweepInterval``.
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
    ///
    /// The first sweep runs shortly after the initialization and is skipped if
    /// one was already performed within the interval, e.g. by the previous launch.
    public var sweepInterval: TimeInterval {
        get { state.withLock { $0.sweepInterval } }
        set { state.withLock { $0.sweepInterval = newValue } }
    }

    /// If `false`, the automatic LRU sweep is disabled. The default value is `true`.
    ///
    /// The scheduled sweeps are skipped while it is off, so turning it back on
    /// resumes them within ``sweepInterval``.
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

    /// The interval between the automatic drains of the staging area, giving
    /// the changes that arrive in quick succession a chance to batch up into a
    /// single pass over the disk. `1` second by default.
    ///
    /// The interval throttles only the automatic drain. ``flush()`` and
    /// ``sweep()`` perform the work themselves and are never held up by it.
    var flushInterval: DispatchTimeInterval {
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

    private let filenameGenerator: FilenameGenerator
    private let onSweepCompleted: (@Sendable () -> Void)?

    /// The serial queue that all of the disk I/O runs on.
    ///
    /// The file operations are synchronous and can block for a long time, which
    /// is what GCD threads are for: running them in a task would occupy one of
    /// the few threads in the cooperative pool for the entire duration of a
    /// write. The queue is serial, so the disk operations never overlap.
    ///
    /// - important: The queue has no QoS of its own. The automatic drain and
    /// the access date updates are submitted at `.utility`, while ``flush()``
    /// and ``sweep()`` are submitted with no QoS class so that they run at the
    /// priority of the task awaiting them. A QoS assigned to the queue
    /// overrides the one assigned to the blocks and would flatten both cases
    /// into one.
    private let ioQueue = DispatchQueue(label: "com.github.kean.Nuke.DataCache.io")

    private struct State {
        /// The changes that are yet to reach the disk.
        var staging = Staging()
        /// A drain is already scheduled on ``ioQueue``. There is never more
        /// than one of them in flight.
        var isFlushScheduled = false
        /// Prevents the automatic drain from running (testing only).
        var isIOSuspended = false
        /// The keys whose access date is yet to reach the disk.
        var pendingTouches = Set<String>()
        /// The number of the access date updates written (testing only).
        var accessDateUpdateCount = 0
        var sizeLimit = 1024 * 1024 * 150
        var sweepInterval: TimeInterval = 1800
        var flushInterval: DispatchTimeInterval = .seconds(1)
        var isSweepEnabled = true
        var trimRatio = 0.7

        /// There is something for the drain to write.
        var hasPendingWork: Bool {
            !staging.isEmpty || !pendingTouches.isEmpty
        }
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
        try self.init(path: path, filenameGenerator: filenameGenerator, sweepDelay: .seconds(5), sweepInterval: nil, onSweepCompleted: nil)
    }

    convenience init(
        name: String,
        filenameGenerator: @escaping FilenameGenerator = DataCache.filename(for:),
        sweepDelay: DispatchTimeInterval,
        sweepInterval: TimeInterval? = nil,
        onSweepCompleted: @escaping @Sendable () -> Void
    ) throws {
        try self.init(path: URL.cachesDirectory.appendingPathComponent(name, isDirectory: true), filenameGenerator: filenameGenerator, sweepDelay: sweepDelay, sweepInterval: sweepInterval, onSweepCompleted: onSweepCompleted)
    }

    private init(
        path: URL,
        filenameGenerator: @escaping FilenameGenerator,
        sweepDelay: DispatchTimeInterval,
        sweepInterval: TimeInterval?,
        onSweepCompleted: (@Sendable () -> Void)?
    ) throws {
        self.path = path
        self.filenameGenerator = filenameGenerator
        self.onSweepCompleted = onSweepCompleted
        if let sweepInterval { // Testing only
            state.withLock { $0.sweepInterval = sweepInterval }
        }
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)
        scheduleSweep(deadline: .now() + sweepDelay)
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
        guard let url = url(for: key), let data = try? Data(contentsOf: url) else {
            return nil
        }
        touchAccessDate(for: key)
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

    /// Refreshes the access date that the LRU sweep ranks the entries by.
    ///
    /// The update is a syscall that can block like any other file operation,
    /// so it joins the staged changes instead of running on the thread that
    /// reads the data, which can be the main one. The reads that arrive within
    /// the same window are written in a single pass.
    private func touchAccessDate(for key: String) {
        state.withLock {
            $0.pendingTouches.insert(key)
            scheduleNextFlush(&$0)
        }
    }

    /// The number of the access date updates written (testing only).
    var accessDateUpdateCount: Int {
        state.withLock { $0.accessDateUpdateCount }
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
        state.withLock {
            change(&$0.staging)
            scheduleNextFlush(&$0)
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

    /// Writes the changes staged so far and waits for them to reach the disk.
    ///
    /// The call performs the work itself instead of waiting for the automatic
    /// drain, so neither the flush interval nor the changes staged after it
    /// hold it up.
    public func flush() async {
        await performIO { self.performPendingChanges() }
    }

    /// Performs a cache sweep, removing the least recently used items that no
    /// longer fit in the cache, and waits for it to finish.
    public func sweep() async {
        await performIO {
            self.performPendingChanges() // The sweep has to see the staged writes
            self.performSweep()
        }
    }

    /// Schedules the drain of the staging area unless one is already scheduled.
    ///
    /// The window gives the changes that arrive in quick succession a chance to
    /// batch up: they are written in a single pass over the disk, and the
    /// repeated writes to the same key are collapsed into one.
    ///
    /// - important: Must be called with the lock held.
    private func scheduleNextFlush(_ state: inout State) {
        guard !state.isFlushScheduled, !state.isIOSuspended, state.hasPendingWork else { return }
        state.isFlushScheduled = true
        // `self` is captured strongly on purpose: the staged data has to reach
        // the disk even if the client releases the cache in the meantime.
        ioQueue.asyncAfter(deadline: .now() + state.flushInterval, qos: .utility) {
            self.flushChangesIfNeeded()
        }
    }

    /// Writes the changes staged so far. Runs on ``ioQueue``.
    private func flushChangesIfNeeded() {
        // Create a snapshot of the recently made changes. The drain is no
        // longer scheduled, so the changes staged from here on schedule the
        // next one instead of joining the snapshot.
        let work: PendingWork? = state.withLock {
            $0.isFlushScheduled = false
            guard !$0.isIOSuspended else {
                return nil // The changes are picked up by `resumeIO()`
            }
            return $0.hasPendingWork ? takePendingWork(&$0) : nil
        }
        guard let work else { return }

        // Apply the snapshot to disk
        performChanges(work)

        // Drain whatever was staged while the snapshot was being written
        state.withLock { scheduleNextFlush(&$0) }
    }

    /// Suspends the automatic drain for the duration of the closure (testing only).
    func withSuspendedIO(_ closure: () -> Void) {
        suspendIO()
        closure()
        resumeIO()
    }

    /// Prevents the automatic drain from running until ``resumeIO()``. The
    /// changes stay in the staging area until then, but ``flush()`` still
    /// writes them.
    func suspendIO() {
        state.withLock { $0.isIOSuspended = true }
    }

    /// Lifts the ``suspendIO()`` suspension and schedules a drain if any
    /// changes accumulated in the meantime.
    private func resumeIO() {
        state.withLock {
            $0.isIOSuspended = false
            scheduleNextFlush(&$0)
        }
    }

    // MARK: - I/O

    /// Runs the blocking work on ``ioQueue`` without occupying a thread from
    /// the cooperative pool while it executes.
    ///
    /// The work carries no QoS class of its own, so GCD runs it at the QoS of
    /// the submitting context – the priority of the task that awaits it. It is
    /// the donation `sync` used to perform, and it matters because the
    /// automatic drain is throttled to `.utility` and an awaited flush is not.
    ///
    /// There is one continuation per call, not per file, so its cost is
    /// negligible next to the disk operations it wraps.
    private func performIO<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            ioQueue.async {
                continuation.resume(returning: work())
            }
        }
    }

    /// The changes and the access dates that are yet to reach the disk.
    private typealias PendingWork = (staging: Staging, touches: Set<String>)

    /// - important: Must be called with the lock held.
    private func takePendingWork(_ state: inout State) -> PendingWork {
        let touches = state.pendingTouches
        state.pendingTouches.removeAll()
        return (state.staging, touches)
    }

    /// Writes the changes staged so far. Runs on ``ioQueue``.
    private func performPendingChanges() {
        let work: PendingWork? = state.withLock {
            $0.hasPendingWork ? takePendingWork(&$0) : nil
        }
        guard let work else { return }
        performChanges(work)
    }

    private func performChanges(_ work: PendingWork) {
        let staging = work.staging
        autoreleasepool {
            if staging.changeRemoveAll != nil {
                performRemoveAll()
            }
            for change in staging.changes.values {
                perform(change)
            }
            performTouches(work.touches)
        }
        state.withLock { $0.staging.flushed(staging) }
    }

    private func performTouches(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        var values = URLResourceValues()
        values.contentAccessDate = Date()
        for key in keys {
            guard var url = url(for: key) else { continue }
            try? url.setResourceValues(values)
        }
        state.withLock { $0.accessDateUpdateCount += keys.count }
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

    /// Schedules the next sweep. The first one runs after a small delay to free
    /// the resources during launch, the rest every ``DataCache/sweepInterval``.
    private func scheduleSweep(deadline: DispatchTime) {
        // `self` is captured weakly: the repeating sweep must not keep the cache alive.
        ioQueue.asyncAfter(deadline: deadline, qos: .utility) { [weak self] in
            guard let self else { return }
            performScheduledSweep()
            scheduleSweep(deadline: .now() + sweepInterval) // Also when skipped
        }
    }

    /// Performs the sweep unless it is disabled or one has already been
    /// performed within the last ``DataCache/sweepInterval``. Runs on ``ioQueue``.
    private func performScheduledSweep() {
        guard isSweepEnabled, isSweepNeeded() else { return }
        performPendingChanges() // The sweep has to see the staged writes
        performSweep()
        updateMetadata { $0.lastSweepDate = Date() }
        onSweepCompleted?()
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