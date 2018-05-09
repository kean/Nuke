// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation

extension DataCache {
    static var shared: DataCache?
}

extension DispatchWorkItem: Cancellable {}

/// Experimental data cache. The public API for disk cache is going to be
/// available in the future versions when it goes out of beta.
internal class DataCache {
    typealias Key = String

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
    
    let path: URL
    
    // Index of entries.
    private let _lock = NSLock()
    private var _index = [Filename: Entry]()
    
    /// The number of seconds between each discard sweep. 30 by default.
    /// The first sweep is run right after the cache is initialzied.
    var sweepInterval: TimeInterval = 30
    private let _algorithm: CacheAlgorithm?

    // Persistence
    private let _rqueue = DispatchQueue(label: "com.github.kean.Nuke.DataCache.ReadQueue")
    private let _wqueue = DispatchQueue(label: "com.github.kean.Nuke.DataCache.WriteQueue") // _wqueue is internal to make it @testable
    
    // Temporary
    var _keyEncoder: (String) -> String? = { return $0 }

    convenience init(name: String, algorithm: CacheAlgorithm? = CacheAlgorithmLRU()) throws {
        guard let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: nil)
        }
        try self.init(path: root.appendingPathComponent(name, isDirectory: true), algorithm: algorithm)
    }
    
    init(path: URL, algorithm: CacheAlgorithm? = CacheAlgorithmLRU()) throws {
        self.path = path
        self._algorithm = algorithm
        
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)

        // Pay a little price upfront to get better performance and more control
        // later (we need this index anyway to perform sweeps). We take advantage
        /// of fast filesystem metadata. Loading an index of cache with 1000 items
        // 64 Kb each (~ 62 Mb total) is almost instantaneous on modern hardware.
        self._rqueue.async {
            // We load index on _rqueue this way we guarantee that index is
            // going to be available by the first time `data(for:completion)` is
            // called, but synchronous calls might return nil.
            self._lock.lock()
            self._loadIndex()
            self._lock.unlock()
            self._wqueue.async {
                self._scheduleSweep()
                self._sweep()
            }
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

    // MARK: Data Accessors

    func filename(for key: Key) -> Filename? {
        return _keyEncoder(key).map(Filename.init(raw:))
    }
    
    subscript(key: Key) -> Data? {
        get {
            guard let filename = self.filename(for: key) else { return nil }
            return _getData(for: filename)
        }
        set {
            guard let filename = self.filename(for: key) else { return }
            if let data = newValue {
                _setData(data, for: filename)
            } else {
                _removeData(for: filename)
            }
        }
    }

    private func _getData(for filename: Filename) -> Data? {
        _lock.lock()
        guard let entry = _index[filename] else {
            _lock.unlock()
            return nil
        }
        entry.accessDate = Date()
        let payload = entry.payload
        _lock.unlock()

        switch payload {
        case let .staged(data): return data
        case let .saved(url): return try? Data(contentsOf: url)
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

    /// Removes all items asynchronously.
    func removeAll() {
        _lock.lock()
        _index.removeAll()
        _lock.unlock()

        _wqueue.async {
            try? FileManager.default.removeItem(at: self.path)
            try? FileManager.default.createDirectory(at: self.path, withIntermediateDirectories: true, attributes: nil)
        }
    }

    // MARK: Flush Changes

    /// Synchronously waits on the callers thread while all the remaining
    /// entries are flushed to disk.
    func flush() {
        // Wait until everything is written and flush keys
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
        guard let algorithm = _algorithm else { return }
        sweep(with: algorithm)
    }

    func sweep(with algorithm: CacheAlgorithm) {
        _wqueue.async {
            self._sweep(with: algorithm)
        }
    }

    private func _sweep() {
        guard let algorithm = _algorithm else { return }
        _sweep(with: algorithm)
    }

    private func _sweep(with algorithm: CacheAlgorithm) {
        _lock.lock()
        let discarded = algorithm.discarded(items: _index.values)
        _removeData(for: discarded.map { $0.filename })
        _lock.unlock()
    }

    // MARK: Inspection

    /// Allows you to inspect the cache contents. This method executes synchronously.
    /// synchronously in the cache's critical section.
    func inspect<T>(_ closure: ([Filename: Entry]) -> T) -> T {
        return _lock.sync { closure(_index) }
    }

    /// The total number of items in the cache.
    var totalCount: Int {
        return _lock.sync { _index.count }
    }

    /// The total size of items in the cache.
    var totalSize: Int {
        return _lock.sync {
            _index.reduce(0) { $0 + ($1.value.fileSize ?? 0) }
        }
    }

    /// Might be underestimdated until all write operation are completed.
    var totalAllocatedSize: Int {
        return _lock.sync {
            _index.reduce(0) { $0 + $1.value.underestimatedSize }
        }
    }

    // MARK: Temporary

    @discardableResult func data(for key: Key, _ completion: @escaping (Data?) -> Void) -> Cancellable {
        let work = DispatchWorkItem { [weak self] in
            completion(self?[key])
        }
        _rqueue.async(execute: work)
        return work
    }

    // MARK: Testing

    func _test_withSuspendedIO(_ closure: () -> Void) {
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
}

/// Protocol that represents a [cache algorithm](https://en.wikipedia.org/wiki/Cache_replacement_policies)
/// (also called *cache replacement policy*).
protocol CacheAlgorithm {
    /// Filters an array of items to contain only items that should be
    /// discarded to make room for the new ones.
    ///
    /// This method gets called periodically by the Cache. The argument is
    /// marked as `inout` to achieve max performance.
    func discarded<Items: Collection>(items: Items) -> [DataCache.Entry] where Items.Element == DataCache.Entry
}

/// Discards least recently used items first.
struct CacheAlgorithmLRU: CacheAlgorithm {
    /// The maximum number of items. `1000` by default.
    var countLimit: Int

    /// Size limit in bytes. `100 Mb` by default.
    var sizeLimit: Int

    /// The `discarded(items:)` method removes items until the total
    /// size of the remaining items is lower then or equal to
    /// `sizeLimit * trimRatio` and the total count is lower then or
    /// equal to `countLimit * trimRatio`. `0.7` by default.
    var trimRatio = 0.7

    /// - parameter countLimit: The maximum number of items. `1000` by default.
    /// - parameter sizeLimit: Size limit in bytes. `100 Mb` by default.
    init(countLimit: Int = 1000, sizeLimit: Int = 1024 * 1024 * 100) {
        self.countLimit = countLimit
        self.sizeLimit = sizeLimit
    }

    /// Discards the least recently used items first.
    func discarded<Items>(items: Items) -> [DataCache.Entry] where Items: Collection, Items.Element == DataCache.Entry {
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
        let sorted = items.sorted {
            // In pratice items must always have `accessDate` at this point
            ($0.accessDate ?? past) < ($1.accessDate ?? past)
        }

        // Remove the items until we satisfy both size and count limits.
        var idx = 0
        while (size > sizeLimit || count > countLimit), idx <= sorted.endIndex {
            size -= sorted[idx].underestimatedSize
            count -= 1
            idx += 1
        }

        // Remove all remaining items
        return Array(sorted[0..<idx])
    }
}
