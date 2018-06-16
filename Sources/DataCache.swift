// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - DataCaching

/// Data cache.
///
/// - warning: The implementation must be thread safe.
public protocol DataCaching {
    func cachedData(for key: String, _ completion: @escaping (Data?) -> Void) -> Cancellable
    func storeData(_ data: Data, for key: String)
}

extension DataCache {
    static var shared: DataCache?
}

// MARK: - DataCache

/// Cache for storing data on disk with LRU cleanup policy (least recently used
/// items are removed first). The elements stored in the cache are automatically
/// discarded if either *cost* or *count* limit is reached.
///
/// Thread-safe.
///
/// - warning: Multiple instances with the same path are *not* allowed as they
/// would conflict with each other.
internal final class DataCache: DataCaching {
    internal typealias Key = String

    /// The maximum number of items. `1000` by default.
    internal var countLimit: Int = 1000

    /// Size limit in bytes. `100 Mb` by default.
    internal var sizeLimit: Int = 1024 * 1024 * 100

    /// When performing a sweep, the cache will remote entries until the size of
    /// the remaining items is lower than or equal to `sizeLimit * trimRatio` and
    /// the total count is lower than or equal to `countLimit * trimRatio`. `0.7`
    /// by default.
    internal var trimRatio = 0.7

    /// The path managed by cache.
    internal let path: URL
    
    // Index & index lock.
    private let _lock = NSLock()
    private var _index = [Filename: Entry]()
    
    /// The number of seconds between each discard sweep. 30 by default.
    /// The first sweep is run right after the cache is initialzied.
    var sweepInterval: TimeInterval = 30

    // Persistence
    private let _rqueue = DispatchQueue(label: "com.github.kean.Nuke.DataCache.ReadQueue")
    private let _wqueue = DispatchQueue(label: "com.github.kean.Nuke.DataCache.WriteQueue")
    
    // Temporary
    var _keyEncoder: (String) -> String? = { return $0 }

    /// Creates a cache instance with a given `name`. The cache creates a directory
    /// with the given `name` in a `.cachesDirectory` in `.userDomainMask`.
    ///
    /// - warning: Multiple instances with the same path are *not* allowed as they
    /// would conflict with each other.
    internal convenience init(name: String) throws {
        guard let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: nil)
        }
        try self.init(path: root.appendingPathComponent(name, isDirectory: true))
    }

    /// Creates a cache instance with a given path.
    ///
    /// - warning: Multiple instances with the same path are *not* allowed as they
    /// would conflict with each other.
    internal init(path: URL) throws {
        self.path = path

        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)

        // Read queue is suspended until we load the index.
        self._rqueue.suspend()

        // Pay a little price upfront to get better performance and more control
        // later (we need this index anyway to perform sweeps). Filesystem metadata
        // is very fast. Loading an index of cache with 1000 items 64 Kb each
        // (~ 62 Mb total) is almost instantaneous on modern hardware.
        self._wqueue.async {
            self._lock.lock()
            self._loadIndex()
            self._lock.unlock()

            // Resume `_rqeueue` guaranteeing that index is available by the
            // time async read methods are performed.
            self._rqueue.resume()
        }
    }
    
    // MARK: Loading Index

    /// Takes advantage of the fast filesystem metadata. Reading contents of
    /// cache directory is not that much slower than, for instance, maintaining
    /// our own persistent index.
    private func _loadIndex() {
        let resourceKeys: Set<URLResourceKey> = [.creationDateKey, .contentAccessDateKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        for url in _contents(keys: Array(resourceKeys)) {
            if let meta = try? url.resourceValues(forKeys: resourceKeys) {
                let filename = Filename(raw: url.lastPathComponent)
                _index[filename] = Entry(filename: filename, url: url, metadata: meta)
            }
        }
    }

    private func _contents(keys: [URLResourceKey]) -> [URL] {
        return (try? FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
    }

    // MARK: DataCaching

    /// Retrieves data from cache for the given key. The completion will be called
    /// syncrhonously if there is no cached data for the given key.
    @discardableResult
    internal func cachedData(for key: Key, _ completion: @escaping (Data?) -> Void) -> Cancellable {
        guard let filename = self.filename(for: key),
            let payload = _getPayload(for: filename) else {
                completion(nil) // Instant miss
                return NoOpCancellable()
        }
        let work = DispatchWorkItem { [weak self] in
            let data = self?._getData(for: payload)
            completion(data)
        }
        _rqueue.async(execute: work)
        return work
    }

    /// Stores data for the given key. The method returns instantly and the data
    /// is written asyncrhonously.
    internal func storeData(_ data: Data, for key: Key) {
        self[key] = data
    }

    /// Removes data for the given key. The method returns instantly, the data
    /// is removed asyncrhonously.
    internal func removeData(for key: Key) {
        self[key] = nil
    }

    /// Removes all items. The method returns instantly, the data is removed
    /// asyncrhonously.
    internal func removeAll() {
        _lock.lock()
        _index.removeAll()
        _lock.unlock()

        _wqueue.async {
            try? FileManager.default.removeItem(at: self.path)
            try? FileManager.default.createDirectory(at: self.path, withIntermediateDirectories: true, attributes: nil)
        }
    }

    // MARK: Data Accessors

    // This is internal for now.

    func filename(for key: Key) -> Filename? {
        return _keyEncoder(key).map(Filename.init(raw:))
    }

    subscript(key: Key) -> Data? {
        get {
            guard let filename = self.filename(for: key),
                let payload = _getPayload(for: filename) else {
                return nil
            }
            return _getData(for: payload)
        }
        set {
            guard let filename = self.filename(for: key) else {
                return
            }
            if let data = newValue {
                _setData(data, for: filename)
            } else {
                _removeData(for: filename)
            }
        }
    }

    private func _getPayload(for filename: Filename) -> Entry.Payload? {
        _lock.lock()
        defer { _lock.unlock() }
        guard let entry = _index[filename] else {
            return nil
        }
        entry.accessDate = Date()
        return entry.payload
    }

    private func _getData(for payload: Entry.Payload) -> Data? {
        switch payload {
        case let .staged(data):
            return data
        case let .saved(url):
            return try? Data(contentsOf: url)
        }
    }

    private func _setData(_ data: Data, for filename: Filename) {
        let entry = Entry(filename: filename, data: data)

        _lock.lock()
        _index[filename] = entry // Replace with the new value
        _lock.unlock()

        _wqueue.async {
            let url = self.path.appendingPathComponent(filename.raw, isDirectory: false)

            try? data.write(to: url)
            let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize

            self._lock.lock()
            entry.payload = .saved(url) // Flushed the changes
            entry.totalFileAllocatedSize = size
            self._lock.unlock()
        }
    }

    private func _removeData(for filename: Filename) {
        _lock.lock()
        _removeData(for: [filename])
        _lock.unlock()
    }

    private func _removeData(for filenames: [Filename]) {
        #if swift(>=4.1)
        let removed = filenames.compactMap { _index.removeValue(forKey: $0) }
        #else
        let removed = filenames.flatMap { _index.removeValue(forKey: $0) }
        #endif
        guard !removed.isEmpty else { return }

        _wqueue.async {
            #if swift(>=4.1)
            let urls = self._lock.sync {
                removed.compactMap { $0.payload.url }
            }
            #else
            let urls = self._lock.sync {
                removed.flatMap { $0.payload.url }
            }
            #endif
            urls.forEach {
                try? FileManager.default.removeItem(at: $0)
            }
        }
    }

    // MARK: Flush Changes

    /// Synchronously waits on the caller's thread while all outstanding disk IO
    /// operations are finished.
    public func flush() {
        _wqueue.sync {}
    }

    // MARK: Sweep

    private func _scheduleSweep() {
        _wqueue.asyncAfter(deadline: .now() + sweepInterval) { [weak self] in
            self?._sweep()
            self?._scheduleSweep()
        }
    }

    func sweep() {
        _wqueue.async {
            self._sweep()
        }
    }

    private func _sweep() {
        _lock.lock()
        let discarded = self._itemsToDicard()
        _removeData(for: discarded.map { $0.filename })
        _lock.unlock()
    }

    /// Discards the least recently used items first.
    private func _itemsToDicard() -> ArraySlice<DataCache.Entry> {
        var items = Array(_index.values)
        guard items.count > 0 else { return [] }

        var size = items.reduce(0) { $0 + $1.underestimatedSize }
        var count = items.count
        let sizeLimit = self.sizeLimit / Int(1 / trimRatio)
        let countLimit = self.countLimit / Int(1 / trimRatio)

        guard size > sizeLimit || count > countLimit else {
            return [] // All good, no need to perform any work.
        }

        // Least recently accessed items first
        let past = Date.distantPast
        items.sort { // Sort in place
            // In pratice items must always have `accessDate` at this point
            ($0.accessDate ?? past) < ($1.accessDate ?? past)
        }

        // Remove the items until we satisfy both size and count limits.
        var idx = 0
        while (size > sizeLimit || count > countLimit), idx <= items.endIndex {
            size -= items[idx].underestimatedSize
            count -= 1
            idx += 1
        }

        // Remove all remaining items
        return items[0..<idx]
    }

    // MARK: Inspection

    /// Allows you to inspect the cache contents. This method executes synchronously.
    /// synchronously in the cache's critical section.
    func inspect<T>(_ closure: ([Filename: Entry]) -> T) -> T {
        return _lock.sync { closure(_index) }
    }

    /// The total number of items in the cache.
    public var totalCount: Int {
        return _lock.sync { _index.count }
    }

    /// The total size of items in the cache.
    public var totalSize: Int {
        return _lock.sync {
            _index.reduce(0) { $0 + ($1.value.fileSize ?? 0) }
        }
    }

    /// Might be underestimdated until all write operation are completed.
    public var totalAllocatedSize: Int {
        return _lock.sync {
            _index.reduce(0) { $0 + $1.value.underestimatedSize }
        }
    }

    // MARK: Testing

    func _testWithSuspendedIO(_ closure: () -> Void) {
        _wqueue.suspend()
        closure()
        _wqueue.resume()
    }

    // MARK: Entry

    final class Entry {
        /// The date the entry was created (`URLResourceKey.creationDateKey`).
        internal(set) var creationDate: Date?

        /// The date the entry was last accessed (`URLResourceKey.contentAccessDateKey`).
        internal(set) var accessDate: Date?

        /// File size in bytes (`URLResourceKey.fileSizeKey`).
        internal(set) var fileSize: Int?

        /// Total size allocated on disk for the file in bytes (number of blocks
        /// times block size) (`URLResourceKey.fileAllocatedSizeKey`).
        ///
        /// The allocated size doesn't become available until the data is
        /// actually written to disk.
        internal(set) var totalFileAllocatedSize: Int?

        var underestimatedSize: Int {
            return totalFileAllocatedSize ?? fileSize ?? 0
        }

        let filename: Filename

        enum Payload {
            case staged(Data)
            case saved(URL)

            var url: URL? {
                if case let .saved(url) = self { return url }
                return nil
            }
        }
        var payload: Payload

        init(filename: Filename, payload: Payload) {
            self.filename = filename
            self.payload = payload
        }

        convenience init(filename: Filename, url: URL, metadata: URLResourceValues) {
            self.init(filename: filename, payload: .saved(url))
            self.creationDate = metadata.creationDate
            self.accessDate = metadata.contentAccessDate
            self.fileSize = metadata.fileSize
            self.totalFileAllocatedSize = metadata.totalFileAllocatedSize
        }

        convenience init(filename: Filename, data: Data) {
            self.init(filename: filename, payload: .staged(data))
            let now = Date()
            self.creationDate = now
            self.accessDate = now
            self.fileSize = data.count
        }
    }

    // MARK: Misc

    struct Filename: Hashable {
        let raw: String

        #if !swift(>=4.1)
        var hashValue: Int {
        return raw.hashValue
        }

        static func == (lhs: DataCache.Filename, rhs: DataCache.Filename) -> Bool {
        return lhs.raw == rhs.raw
        }
        #endif
    }
}
