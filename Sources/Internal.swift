// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

// MARK: - Lock

extension NSLock {
    func sync<T>(_ closure: () -> T) -> T {
        lock()
        defer { unlock() }
        return closure()
    }
}

// MARK: - RateLimiter

/// Controls the rate at which the work is executed. Uses the classic [token
/// bucket](https://en.wikipedia.org/wiki/Token_bucket) algorithm.
///
/// The main use case for rate limiter is to support large (infinite) collections
/// of images by preventing trashing of underlying systems, primary URLSession.
///
/// The implementation supports quick bursts of requests which can be executed
/// without any delays when "the bucket is full". This is important to prevent
/// rate limiter from affecting "normal" requests flow.
final class RateLimiter {
    private let bucket: TokenBucket
    private let queue: DispatchQueue
    private var pending = LinkedList<Work>() // fast append, fast remove first
    private var isExecutingPendingTasks = false

    typealias Work = () -> Bool

    /// Initializes the `RateLimiter` with the given configuration.
    /// - parameter queue: Queue on which to execute pending tasks.
    /// - parameter rate: Maximum number of requests per second. 80 by default.
    /// - parameter burst: Maximum number of requests which can be executed without
    /// any delays when "bucket is full". 25 by default.
    init(queue: DispatchQueue, rate: Int = 80, burst: Int = 25) {
        self.queue = queue
        self.bucket = TokenBucket(rate: Double(rate), burst: Double(burst))
    }

    /// - parameter closure: Returns `true` if the close was executed, `false`
    /// if the work was cancelled.
    func execute( _ work: @escaping Work) {
        if !pending.isEmpty || !bucket.execute(work) {
            pending.append(work)
            setNeedsExecutePendingTasks()
        }
    }

    private func setNeedsExecutePendingTasks() {
        guard !isExecutingPendingTasks else {
            return
        }
        isExecutingPendingTasks = true
        // Compute a delay such that by the time the closure is executed the
        // bucket is refilled to a point that is able to execute at least one
        // pending task. With a rate of 80 tasks we expect a refill every ~26 ms
        // or as soon as the new tasks are added.
        let delay = Int(2.1 * (1000 / bucket.rate)) // 14 ms for rate 80 (default)
        let bounds = min(100, max(15, delay))
        queue.asyncAfter(deadline: .now() + .milliseconds(bounds), execute: executePendingTasks)
    }

    private func executePendingTasks() {
        while let node = pending.first, bucket.execute(node.value) {
            pending.remove(node)
        }
        isExecutingPendingTasks = false
        if !pending.isEmpty { // Not all pending items were executed
            setNeedsExecutePendingTasks()
        }
    }
}

private final class TokenBucket {
    let rate: Double
    private let burst: Double // maximum bucket size
    private var bucket: Double
    private var timestamp: TimeInterval // last refill timestamp

    /// - parameter rate: Rate (tokens/second) at which bucket is refilled.
    /// - parameter burst: Bucket size (maximum number of tokens).
    init(rate: Double, burst: Double) {
        self.rate = rate
        self.burst = burst
        self.bucket = burst
        self.timestamp = CFAbsoluteTimeGetCurrent()
    }

    /// Returns `true` if the closure was executed, `false` if dropped.
    func execute(_ work: () -> Bool) -> Bool {
        refill()
        guard bucket >= 1.0 else {
            return false // bucket is empty
        }
        if work() {
            bucket -= 1.0 // work was cancelled, no need to reduce the bucket
        }
        return true
    }

    private func refill() {
        let now = CFAbsoluteTimeGetCurrent()
        bucket += rate * max(0, now - timestamp) // rate * (time delta)
        timestamp = now
        if bucket > burst { // prevent bucket overflow
            bucket = burst
        }
    }
}

// MARK: - Operation

final class Operation: Foundation.Operation {
    private var _isExecuting = Atomic(false)
    private var _isFinished = Atomic(false)
    private var isFinishCalled = Atomic(false)

    override var isExecuting: Bool {
        set {
            guard _isExecuting.value != newValue else {
                fatalError("Invalid state, operation is already (not) executing")
            }
            willChangeValue(forKey: "isExecuting")
            _isExecuting.value = newValue
            didChangeValue(forKey: "isExecuting")
        }
        get {
            _isExecuting.value
        }
    }
    override var isFinished: Bool {
        set {
            guard !_isFinished.value else {
                fatalError("Invalid state, operation is already finished")
            }
            willChangeValue(forKey: "isFinished")
            _isFinished.value = newValue
            didChangeValue(forKey: "isFinished")
        }
        get {
            _isFinished.value
        }
    }

    typealias Starter = (_ finish: @escaping () -> Void) -> Void
    private let starter: Starter

    init(starter: @escaping Starter) {
        self.starter = starter
    }

    override func start() {
        guard !isCancelled else {
            isFinished = true
            return
        }
        isExecuting = true
        starter { [weak self] in
            self?._finish()
        }
    }

    private func _finish() {
        // Make sure that we ignore if `finish` is called more than once.
        if isFinishCalled.swap(to: true, ifEqual: false) {
            isExecuting = false
            isFinished = true
        }
    }
}

// MARK: - LinkedList

/// A doubly linked list.
final class LinkedList<Element> {
    // first <-> node <-> ... <-> last
    private(set) var first: Node?
    private(set) var last: Node?

    deinit {
        removeAll()
    }

    var isEmpty: Bool {
        last == nil
    }

    /// Adds an element to the end of the list.
    @discardableResult
    func append(_ element: Element) -> Node {
        let node = Node(value: element)
        append(node)
        return node
    }

    /// Adds a node to the end of the list.
    func append(_ node: Node) {
        if let last = last {
            last.next = node
            node.previous = last
            self.last = node
        } else {
            last = node
            first = node
        }
    }

    func remove(_ node: Node) {
        node.next?.previous = node.previous // node.previous is nil if node=first
        node.previous?.next = node.next // node.next is nil if node=last
        if node === last {
            last = node.previous
        }
        if node === first {
            first = node.next
        }
        node.next = nil
        node.previous = nil
    }

    func removeAll() {
        // avoid recursive Nodes deallocation
        var node = first
        while let next = node?.next {
            node?.next = nil
            next.previous = nil
            node = next
        }
        last = nil
        first = nil
    }

    final class Node {
        let value: Element
        fileprivate var next: Node?
        fileprivate var previous: Node?

        init(value: Element) {
            self.value = value
        }
    }
}

// MARK: - ResumableData

/// Resumable data support. For more info see:
/// - https://developer.apple.com/library/content/qa/qa1761/_index.html
struct ResumableData {
    let data: Data
    let validator: String // Either Last-Modified or ETag

    init?(response: URLResponse, data: Data) {
        // Check if "Accept-Ranges" is present and the response is valid.
        guard !data.isEmpty,
            let response = response as? HTTPURLResponse,
            response.statusCode == 200 /* OK */ || response.statusCode == 206, /* Partial Content */
            let acceptRanges = response.allHeaderFields["Accept-Ranges"] as? String,
            acceptRanges.lowercased() == "bytes",
            let validator = ResumableData._validator(from: response) else {
                return nil
        }

        // NOTE: https://developer.apple.com/documentation/foundation/httpurlresponse/1417930-allheaderfields
        // HTTP headers are case insensitive. To simplify your code, certain
        // header field names are canonicalized into their standard form.
        // For example, if the server sends a content-length header,
        // it is automatically adjusted to be Content-Length.

        self.data = data; self.validator = validator
    }

    private static func _validator(from response: HTTPURLResponse) -> String? {
        if let entityTag = response.allHeaderFields["ETag"] as? String {
            return entityTag // Prefer ETag
        }
        // There seems to be a bug with ETag where HTTPURLResponse would canonicalize
        // it to Etag instead of ETag
        // https://bugs.swift.org/browse/SR-2429
        if let entityTag = response.allHeaderFields["Etag"] as? String {
            return entityTag // Prefer ETag
        }
        if let lastModified = response.allHeaderFields["Last-Modified"] as? String {
            return lastModified
        }
        return nil
    }

    func resume(request: inout URLRequest) {
        var headers = request.allHTTPHeaderFields ?? [:]
        // "bytes=1000-" means bytes from 1000 up to the end (inclusive)
        headers["Range"] = "bytes=\(data.count)-"
        headers["If-Range"] = validator
        request.allHTTPHeaderFields = headers
    }

    // Check if the server decided to resume the response.
    static func isResumedResponse(_ response: URLResponse) -> Bool {
        // "206 Partial Content" (server accepted "If-Range")
        (response as? HTTPURLResponse)?.statusCode == 206
    }

    // MARK: Storing Resumable Data

    /// Shared between multiple pipelines. Thread safe. In the future version we
    /// might feature more customization options.
    static var cache = Cache<String, ResumableData>(costLimit: 32 * 1024 * 1024, countLimit: 100)
    // internal only for testing purposes

    static func removeResumableData(for request: URLRequest) -> ResumableData? {
        guard let url = request.url?.absoluteString else {
            return nil
        }
        return cache.removeValue(forKey: url)
    }

    static func storeResumableData(_ data: ResumableData, for request: URLRequest) {
        guard let url = request.url?.absoluteString else {
            return
        }
        cache.set(data, forKey: url, cost: data.data.count)
    }
}

// MARK: - Atomic

/// A thread-safe value wrapper.
final class Atomic<T> {
    private var _value: T
    private let lock = NSLock()

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        get {
            lock.lock()
            let value = _value
            lock.unlock()
            return value
        }
        set {
            lock.lock()
            _value = newValue
            lock.unlock()
        }
    }
}

extension Atomic where T: Equatable {
    /// "Compare and Swap"
    func swap(to newValue: T, ifEqual oldValue: T) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard _value == oldValue else {
            return false
        }
        _value = newValue
        return true
    }
}

extension Atomic where T == Int {
    /// Atomically increments the value and retruns a new incremented value.
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }

        _value += 1
        return _value
    }
}

// MARK: - Misc

import CommonCrypto

extension String {
    /// Calculates SHA1 from the given string and returns its hex representation.
    ///
    /// ```swift
    /// print("http://test.com".sha1)
    /// // prints "50334ee0b51600df6397ce93ceed4728c37fee4e"
    /// ```
    var sha1: String? {
        guard let input = self.data(using: .utf8) else {
            return nil
        }

        let hash = input.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [UInt8] in
            var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            CC_SHA1(bytes.baseAddress, CC_LONG(input.count), &hash)
            return hash
        }

        return hash.map({ String(format: "%02x", $0) }).joined()
    }
}

// MARK: - Log

final class Log {
    private let log: OSLog
    private let name: StaticString
    private let signpostsEnabled: Bool

    init(_ log: OSLog, _ name: StaticString, _ signpostsEnabled: Bool = ImagePipeline.Configuration.isSignpostLoggingEnabled) {
        self.log = log
        self.name = name
        self.signpostsEnabled = signpostsEnabled
    }

    // MARK: Signposts

    func signpost(_ type: SignpostType, _ message: @autoclosure () -> String) {
        guard signpostsEnabled else { return }
        signpost(type, "%{public}s", message())
    }

    func signpost(_ type: SignpostType) {
        guard signpostsEnabled else { return }
        if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *) {
            os_signpost(type.os, log: log, name: name, signpostID: signpostID)
        }
    }

    // Unfortunately, there is no way to wrap os_signpost which takes variadic
    // arguments, because Swift implicitly wraps `arguments CVarArg...` from `log`
    // into an array and passes the array to `os_signpost` which is not what
    // we expect. So in this scenario we have to limit the number of arguments
    // to one, there is no way to pass more. For more info see https://stackoverflow.com/questions/50937765/why-does-wrapping-os-log-cause-doubles-to-not-be-logged-correctly
    func signpost(_ type: SignpostType, _ format: StaticString, _ argument: CVarArg) {
        guard signpostsEnabled else { return }
        if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *) {
            os_signpost(type.os, log: log, name: name, signpostID: signpostID, format, argument)
        }
    }

    @available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
    var signpostID: OSSignpostID {
        OSSignpostID(log: log, object: self)
    }
}

private let byteFormatter = ByteCountFormatter()

extension Log {
    static func bytes(_ count: Int) -> String {
        bytes(Int64(count))
    }

    static func bytes(_ count: Int64) -> String {
        byteFormatter.string(fromByteCount: count)
    }
}

enum SignpostType {
    case begin, event, end

    @available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
    var os: OSSignpostType {
        switch self {
        case .begin: return .begin
        case .event: return .event
        case .end: return .end
        }
    }
}
