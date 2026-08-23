// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

/// Prefetches and caches images to eliminate delays when requesting the same
/// images later.
///
/// The prefetcher cancels all of the outstanding tasks when deallocated.
///
/// All ``ImagePrefetcher`` methods are thread-safe and are optimized to be used
/// even from the main thread during scrolling.
@ImagePipelineActor
public final class ImagePrefetcher: Sendable {
    /// Pauses the prefetching.
    ///
    /// - note: When you pause, the prefetcher will finish outstanding tasks
    /// (by default, there are only 2 at a time), and pause the rest.
    nonisolated public var isPaused: Bool {
        get { queue.isSuspended }
        set { queue.isSuspended = newValue }
    }

    /// The priority of the requests. By default, ``ImageRequest/Priority-swift.enum/low``.
    ///
    /// Changing the priority also changes the priority of all of the outstanding
    /// tasks managed by the prefetcher.
    nonisolated public var priority: ImageRequest.Priority {
        get { _priority.withLock { $0 } }
        set {
            let didChange = _priority.withLock {
                guard $0 != newValue else { return false }
                $0 = newValue
                return true
            }
            guard didChange else { return }
            Task { @ImagePipelineActor in self.didUpdatePriority(to: newValue) }
        }
    }
    private nonisolated let _priority = OSAllocatedUnfairLock(initialState: ImageRequest.Priority.low)

    /// Prefetching destination.
    @frozen public enum Destination: Sendable {
        /// Prefetches the image and stores it in both the memory and the disk
        /// cache (make sure to enable it).
        case memoryCache

        /// Prefetches the image data and stores it in disk caches. It does not
        /// require decoding the image data and therefore requires less CPU.
        ///
        /// - important: This option is incompatible with ``ImagePipeline/DataCachePolicy/automatic``
        /// (for requests with processors) and ``ImagePipeline/DataCachePolicy/storeEncodedImages``.
        case diskCache
    }

    /// The closure that gets called when the prefetching completes for all the
    /// scheduled requests. The closure is always called on completion,
    /// regardless of whether the requests succeed or some fail.
    ///
    /// The closure runs every time the prefetcher runs out of outstanding work,
    /// which includes the batches that finish without starting a single task:
    /// an empty list of requests, or one where every image is already in the
    /// memory cache.
    nonisolated public var didComplete: (@MainActor @Sendable () -> Void)? {
        get { _didComplete.withLock { $0 } }
        set { _didComplete.withLock { $0 = newValue } }
    }
    private nonisolated let _didComplete = OSAllocatedUnfairLock<(@MainActor @Sendable () -> Void)?>(initialState: nil)

    private let pipeline: ImagePipeline
    private let destination: Destination
    private var tasks = [TaskLoadImageKey: PrefetchTask]()
    let queue: TaskQueue // internal for testing

    /// The number of batches that were scheduled but haven't reached the
    /// pipeline actor yet. They count as outstanding work: without it,
    /// ``waitUntilIdle()`` called right after ``startPrefetching(with:)-718dg``
    /// would return before the batch it is waiting for even starts.
    private nonisolated let _pendingBatchCount = OSAllocatedUnfairLock(initialState: 0)

    private var isIdle: Bool {
        tasks.isEmpty && _pendingBatchCount.withLock { $0 } == 0
    }

    /// Initializes the ``ImagePrefetcher`` instance.
    ///
    /// - parameters:
    ///   - pipeline: The pipeline used for loading images.
    ///   - destination: By default load images in all cache layers.
    ///   - maxConcurrentRequestCount: 2 by default.
    nonisolated public init(
        pipeline: ImagePipeline = ImagePipeline.shared,
        destination: Destination = .memoryCache,
        maxConcurrentRequestCount: Int = 2
    ) {
        self.pipeline = pipeline
        self.destination = destination
        self.queue = TaskQueue(maxConcurrentOperationCount: maxConcurrentRequestCount)
    }

    nonisolated deinit {
        // Nothing else is going to produce an event, and a stream that never
        // finishes leaves whoever iterates it suspended forever.
        for continuation in streamContinuations.values {
            continuation.finish()
        }
        let tasks = self.tasks.values
        Task { @ImagePipelineActor in
            for task in tasks {
                task.cancel()
            }
        }
    }

    /// Starts prefetching images for the given URL.
    ///
    /// See also ``startPrefetching(with:)-718dg`` that works with ``ImageRequest``.
    nonisolated public func startPrefetching(with urls: [URL]) {
        startPrefetching(with: urls.map { ImageRequest(url: $0) })
    }

    /// Starts prefetching images for the given requests.
    ///
    /// When you need to display the same image later, use the ``ImagePipeline``
    /// or the view extensions to load it as usual. The pipeline will take care
    /// of coalescing the requests to avoid any duplicate work.
    ///
    /// The priority of the requests is set to the priority of the prefetcher
    /// (`.low` by default).
    ///
    /// See also ``startPrefetching(with:)-1jef2`` that works with `URL`.
    nonisolated public func startPrefetching(with requests: [ImageRequest]) {
        _pendingBatchCount.withLock { $0 += 1 }
        Task { @ImagePipelineActor in
            self._startPrefetching(with: requests)
        }
    }

    private func _startPrefetching(with requests: [ImageRequest]) {
        _pendingBatchCount.withLock { $0 -= 1 }
        let currentPriority = _priority.withLock { $0 }
        for request in requests {
            var request = request
            if currentPriority != request.priority {
                request.priority = currentPriority
            }
            _startPrefetching(with: request)
        }
        sendCompletionIfNeeded()
    }

    private func _startPrefetching(with request: ImageRequest) {
        guard pipeline.cache[request] == nil else {
            return
        }
        let key = TaskLoadImageKey(request)
        guard tasks[key] == nil else {
            return
        }
        let task = PrefetchTask(request: request, key: key)
        let pipeline = self.pipeline
        let isDataTask = destination == .diskCache
        let operation = queue.add { [weak self] in
            let imageTask = pipeline.makeStartedImageTask(with: task.request, isDataTask: isDataTask)
            task.imageTask = imageTask
            let result: Result<ImageResponse, ImagePipeline.Error>
            do throws(ImagePipeline.Error) {
                result = .success(try await imageTask.response)
            } catch {
                result = .failure(error)
            }
            self?._remove(task, result: result)
        }
        operation.priority = request.priority.taskPriority
        task.operation = operation
        tasks[key] = task
        _dispatch(.didStartPrefetching(request))
    }

    private func _remove(_ task: PrefetchTask, result: Result<ImageResponse, ImagePipeline.Error>) {
        guard tasks[task.key] === task else { return }
        tasks[task.key] = nil
        _dispatch(.didFinishPrefetching(task.request, result))
        sendCompletionIfNeeded()
    }

    private func sendCompletionIfNeeded() {
        guard isIdle else { return }
        _dispatch(.didComplete)
        if let callback = didComplete {
            DispatchQueue.main.async(execute: callback)
        }
    }

    /// Stops prefetching images for the given URLs and cancels outstanding
    /// requests.
    ///
    /// See also ``stopPrefetching(with:)-8cdam`` that works with ``ImageRequest``.
    nonisolated public func stopPrefetching(with urls: [URL]) {
        stopPrefetching(with: urls.map { ImageRequest(url: $0) })
    }

    /// Stops prefetching images for the given requests and cancels outstanding
    /// requests.
    ///
    /// You don't need to balance the number of `start` and `stop` requests.
    /// If you have multiple screens with prefetching, create multiple instances
    /// of ``ImagePrefetcher``.
    ///
    /// See also ``stopPrefetching(with:)-2tcyq`` that works with `URL`.
    nonisolated public func stopPrefetching(with requests: [ImageRequest]) {
        Task { @ImagePipelineActor in
            // Nothing to complete if the prefetcher was already idle, and the
            // collection view calls this on every scroll.
            let wasBusy = !self.tasks.isEmpty
            for request in requests {
                self._stopPrefetching(with: request)
            }
            if wasBusy {
                self.sendCompletionIfNeeded()
            }
        }
    }

    private func _stopPrefetching(with request: ImageRequest) {
        if let task = tasks.removeValue(forKey: TaskLoadImageKey(request)) {
            task.cancel()
            _dispatch(.didFinishPrefetching(task.request, .failure(.cancelled)))
        }
    }

    /// Stops all prefetching tasks.
    nonisolated public func stopPrefetching() {
        Task { @ImagePipelineActor in
            let wasBusy = !self.tasks.isEmpty
            for task in self.tasks.values {
                task.cancel()
                self._dispatch(.didFinishPrefetching(task.request, .failure(.cancelled)))
            }
            self.tasks.removeAll()
            if wasBusy {
                self.sendCompletionIfNeeded()
            }
        }
    }

    // MARK: - Events

    /// An event produced by the prefetcher.
    @frozen public enum Event: Sendable {
        /// The prefetcher started prefetching the given request.
        ///
        /// Not sent for the requests the prefetcher skips: the images that are
        /// already in the memory cache, and the requests equivalent to the ones
        /// it is already prefetching.
        case didStartPrefetching(ImageRequest)

        /// The prefetcher finished prefetching the given request, successfully
        /// or not. Sent exactly once for every ``Event/didStartPrefetching(_:)``.
        ///
        /// The requests cancelled with ``ImagePrefetcher/stopPrefetching(with:)-8cdam``
        /// finish with ``ImagePipeline/Error/cancelled``.
        case didFinishPrefetching(ImageRequest, Result<ImageResponse, ImagePipeline.Error>)

        /// The prefetcher ran out of outstanding work – the stream equivalent
        /// of ``ImagePrefetcher/didComplete``, sent under the same conditions.
        case didComplete
    }

    /// The stream of events produced by the prefetcher.
    ///
    /// ```swift
    /// for await event in prefetcher.events {
    ///     if case .didFinishPrefetching(let request, .failure(let error)) = event {
    ///         report(error, for: request)
    ///     }
    /// }
    /// ```
    ///
    /// Every access creates a new independent stream. Unlike a task, which has
    /// an outcome to replay, a prefetcher outlives its batches: a stream only
    /// delivers the events produced after it is created, and it finishes only
    /// when the prefetcher is deallocated. Stop iterating, or cancel the task
    /// that iterates, to unsubscribe earlier.
    ///
    /// - note: A stream buffers the events that the consumer hasn't picked up
    /// yet, so a slow consumer never misses one.
    /// - note: Subscribing reaches the pipeline actor asynchronously, so the
    /// events produced in between are missed. Use ``waitUntilIdle()`` instead
    /// of watching for ``Event/didComplete`` right after scheduling a batch.
    nonisolated public var events: AsyncStream<Event> {
        AsyncStream { continuation in
            Task { @ImagePipelineActor in
                self._subscribe(continuation)
            }
        }
    }

    /// Waits until the prefetcher runs out of outstanding work, returning
    /// immediately if it is already idle.
    ///
    /// ```swift
    /// prefetcher.startPrefetching(with: urls)
    /// await prefetcher.waitUntilIdle()
    /// ```
    ///
    /// A convenience over ``events``: it returns on the first
    /// ``Event/didComplete``. Unlike subscribing to the stream, it is safe to
    /// call right after scheduling a batch – the batches that haven't reached
    /// the pipeline actor yet count as outstanding work.
    ///
    /// - important: The prefetcher is shared by everything that schedules work
    /// on it, so this waits for all of the outstanding batches, not only for
    /// the ones scheduled by the caller.
    public func waitUntilIdle() async {
        guard !isIdle else { return }
        for await event in _makeStream() {
            if case .didComplete = event {
                return
            }
        }
    }

    private var streamContinuations = [Int: AsyncStream<Event>.Continuation]()
    private var nextStreamId = 0

    var subscriptionCount: Int { streamContinuations.count } // internal for testing

    /// Creates a stream and subscribes it synchronously, which the async
    /// ``events`` path can't do – that's what makes ``waitUntilIdle()`` safe
    /// to call right after scheduling a batch.
    private func _makeStream() -> AsyncStream<Event> {
        AsyncStream { continuation in
            _subscribe(continuation)
        }
    }

    private func _subscribe(_ continuation: AsyncStream<Event>.Continuation) {
        nextStreamId += 1
        let id = nextStreamId
        streamContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @ImagePipelineActor in
                self?.streamContinuations[id] = nil
            }
        }
    }

    private func _dispatch(_ event: Event) {
        for continuation in streamContinuations.values {
            continuation.yield(event)
        }
    }

    private func didUpdatePriority(to priority: ImageRequest.Priority) {
        let taskPriority = priority.taskPriority
        for task in tasks.values {
            // Updating the request covers the tasks that haven't started yet:
            // it is what the operation body passes to the pipeline when it runs.
            task.request.priority = priority
            task.imageTask?.priority = priority
            task.operation?.priority = taskPriority
        }
    }

    @ImagePipelineActor
    private final class PrefetchTask: Sendable {
        let key: TaskLoadImageKey
        /// Mutable on purpose: the prefetcher priority can change in the window
        /// between the operation being scheduled and its body running, and the
        /// body is what passes the request to the pipeline. Once ``imageTask``
        /// exists, the priority is updated on it instead.
        var request: ImageRequest
        weak var imageTask: ImageTask?
        /// Retained on purpose (same as ``AsyncTask/operation``): it is the only
        /// way to cancel the prefetch in the window between the operation being
        /// scheduled and its body running, and the body is what creates
        /// ``imageTask``. It's the window the standard "start prefetching, then
        /// immediately stop it" pattern lands in.
        var operation: TaskQueue.Operation?

        init(request: ImageRequest, key: TaskLoadImageKey) {
            self.request = request
            self.key = key
        }

        // When task is cancelled, it is removed from the prefetcher and can
        // never get cancelled twice.
        func cancel() {
            operation?.cancel()
            imageTask?._cancelTask()
        }
    }
}
