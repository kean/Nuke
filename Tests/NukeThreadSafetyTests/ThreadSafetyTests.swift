// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

@testable import Nuke
import Testing
import Foundation
import os

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

@Suite(.timeLimit(.minutes(5)))
struct ThreadSafetyTests {
    @Test func imagePipelineThreadSafety() async {
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        await performPipelineThreadSafetyTest(pipeline)

        _ = (dataLoader, pipeline)
    }

    @Test func imagePipelineThreadSafetyWithDiagnostics() async {
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDiagnosticsEnabled = true
        }
        let toggler = Task.detached {
            for _ in 0..<100 {
                pipeline.diagnostics.isEnabled.toggle()
                await Task.yield()
            }
            pipeline.diagnostics.isEnabled = true
        }

        await performPipelineThreadSafetyTest(pipeline)
        await toggler.value

        _ = (dataLoader, pipeline)
    }

    @Test func sharingConfigurationBetweenPipelines() async { // Especially operation queues
        var configuration = ImagePipeline.Configuration()
        configuration.dataLoader = MockDataLoader()
        configuration.imageCache = nil

        let pipelines = [
            ImagePipeline(configuration: configuration),
            ImagePipeline(configuration: configuration),
            ImagePipeline(configuration: configuration)
        ]

        for pipeline in pipelines {
            await performPipelineThreadSafetyTest(pipeline)
        }

        _ = pipelines
    }

    /// Streams created on many threads while a task sends its events. Each one
    /// starts from the state the task recorded before it was created and then
    /// receives every later event exactly once and in order.
    @Test func imageTaskEventsThreadSafety() async {
        let pipeline = ImagePipeline {
            $0.dataLoader = ChunkedDataLoader(data: Test.data(name: "progressive", extension: "jpeg"), chunkCount: 16)
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.makeImageDecoder = { _ in ImageDecoders.Empty(isProgressive: true) }
        }

        for index in 0..<20 {
            // Given a task that records its events in the order it sends them
            let sent = OSAllocatedUnfairLock<[ImageTask.Event]>(initialState: [])
            let request = ImageRequest(url: URL(string: "http://example.com/\(index).jpeg"))
            let task = pipeline.makeStartedImageTask(with: request) { event, _ in
                sent.withLock { $0.append(event) }
            }

            // When
            let streams = await makeStreamsOnManyThreads(for: task)

            // Then
            await Task { @ImagePipelineActor in }.value // `onEvent` is called after the streams get the event
            let events = sent.withLock { $0 }.map(EventKey.init)
            #expect(events.contains { if case .preview = $0 { true } else { false } })
            for stream in streams {
                let received = await stream.events.reduce(into: [EventKey]()) { $0.append(EventKey($1)) }
                #expect(stream.isExpected(received, sent: events), "\(received)")
            }
        }
    }

    /// Streams created on many threads while tasks finish – on a memory cache
    /// hit, as the pipeline starts the task, or on a cancellation – each
    /// receive the result the task finished with, exactly once.
    @Test func imageTaskTerminalEventThreadSafety() async {
        let dataLoader = MockDataLoader()
        dataLoader.isSuspended = true
        let imageCache = ImageCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
        }

        for index in 0..<200 {
            // Given a request that is either in the memory cache or never loads
            let request = ImageRequest(url: URL(string: "http://example.com/\(index).jpeg"))
            let isCached = index.isMultiple(of: 2)
            if isCached {
                imageCache[request] = Test.container
            }

            // When the task finishes – cancelled, unless it's a cache hit –
            // while streams are created for it
            let (task, streams) = await makeStreamsAcrossTheTerminalEvent(of: request, in: pipeline, cancels: !isCached)

            // Then
            _ = try? await task.response
            for stream in streams {
                let received = await stream.reduce(into: [String]()) { $0.append(name(of: $1)) }
                #expect(received == [isCached ? "success" : "cancelled"], "\(index)")
            }
        }
    }

    @Test func prefetcherThreadSafety() {
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }

        let prefetcher = ImagePrefetcher(pipeline: pipeline)

        @Sendable func makeRequests() -> [ImageRequest] {
            return (0...Int.random(in: 0..<30)).map { _ in
                return ImageRequest(url: URL(string: "http://\(Int.random(in: 0..<15))")!)
            }
        }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        for _ in 0...300 {
            queue.addOperation {
                prefetcher.stopPrefetching(with: makeRequests())
                prefetcher.startPrefetching(with: makeRequests())
                // The prefetcher reads `didComplete` on the pipeline actor
                // every time it runs out of work.
                prefetcher.didComplete = Bool.random() ? nil : { @MainActor @Sendable in }
                _ = prefetcher.didComplete
                prefetcher.priority = Bool.random() ? .high : .low
                prefetcher.isPaused = false
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        prefetcher.stopPrefetching()
    }

    @Test func imageCacheThreadSafety() {
        let cache = ImageCache()

        @Sendable func rnd_cost() -> Int {
            return (2 + Int.random(in: 0..<20)) * 1024 * 1024
        }

        var ops = [@Sendable () -> Void]()

        for _ in 0..<10 { // those ops happen more frequently
            ops += [
                { cache[_request(index: Int.random(in: 0..<10))] = ImageContainer(image: Test.image) },
                { cache[_request(index: Int.random(in: 0..<10))] = nil },
                { let _ = cache[_request(index: Int.random(in: 0..<10))] }
            ]
        }

        ops += [
            { cache.trim(toCost: rnd_cost()) },
            { cache.removeAll() }
        ]

#if os(iOS) || os(tvOS) || os(visionOS)
        ops.append {
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        }
        ops.append {
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        }
#endif

        let finalOps = ops
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5

        for _ in 0..<10000 {
            queue.addOperation {
                finalOps.randomElement()?()
            }
        }

        queue.waitUntilAllOperationsAreFinished()
    }

    // MARK: - DataCache

    @Test func dataCacheThreadSafety() async throws {
        let cache = try DataCache(name: UUID().uuidString, filenameGenerator: { $0 })

        let data = Data(repeating: 1, count: 256 * 1024)

        for idx in 0..<500 {
            cache["\(idx)"] = data
        }
        await cache.flush()

        // The point of the test is to race the accessors, not to measure the
        // throughput, so keep the same number of operations in flight the
        // OperationQueue this replaced allowed.
        let maxConcurrentTaskCount = 5
        var operations: [@Sendable () async -> Void] = []
        for _ in 0..<5 {
            for idx in 0..<500 {
                operations.append {
                    _ = cache["\(idx)"]
                }
                operations.append {
                    cache["\(idx)"] = data
                    await cache.flush()
                }
            }
        }

        await withTaskGroup(of: Void.self) { group in
            var running = 0
            for operation in operations {
                if running == maxConcurrentTaskCount {
                    await group.next()
                    running -= 1
                }
                group.addTask(operation: operation)
                running += 1
            }
        }
    }

    @Test func dataCacheMultipleThreadAccess() async throws {
        let cache = try DataCache(name: UUID().uuidString)

        let aURL = URL(string: "https://example.com/image-01-small.jpeg")!
        let imageData = Test.data(name: "fixture", extension: "jpeg")

        let expectation = TestExpectation()

        let pipeline = ImagePipeline {
            $0.dataCache = cache
            $0.dataLoader = MockDataLoader()
        }
        pipeline.cache.storeCachedData(imageData, for: ImageRequest(url: aURL))
        pipeline.loadImage(with: aURL) { result in
            switch result {
            case .success(let response):
                if response.cacheType == .memory || response.cacheType == .disk {
                    expectation.fulfill()
                } else {
                    Issue.record("didn't load that just cached image data: \(response)")
                }
            case .failure:
                Issue.record("didn't load that just cached image data")
            }
        }

        await expectation.wait()

        try? FileManager.default.removeItem(at: cache.path)
    }
}

@Suite(.timeLimit(.minutes(5)))
struct RandomizedTests {
    @Test func imagePipeline() async {
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isRateLimiterEnabled = false
        }

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 8

        @Sendable func every(_ count: Int) -> Bool {
            return Int.random(in: 0..<Int.max) % count == 0
        }

        @Sendable func randomRequest() -> ImageRequest {
            let url = URL(string: "\(Test.url)/\(Int.random(in: 0..<50))")!
            var request = ImageRequest(url: url)
            request.priority = every(2) ? .high : .normal
            if every(3) {
                let size = every(2) ? CGSize(width: 40, height: 40) : CGSize(width: 60, height: 60)
                request.processors = [ImageProcessors.Resize(size: size, contentMode: .aspectFit)]
            }
            return request
        }

        @Sendable func randomSleep() {
            let ms = TimeInterval.random(in: 0 ..< 100) / 1000.0
            Thread.sleep(forTimeInterval: ms)
        }

        let group = DispatchGroup()

        for _ in 0..<1000 {
            group.enter()
            queue.addOperation {
                randomSleep()

                let request = randomRequest()
                let shouldCancel = every(3)

                let task = pipeline.loadImage(with: request) { _ in
                    if !shouldCancel {
                        group.leave()
                    }
                }

                if shouldCancel {
                    queue.addOperation {
                        randomSleep()
                        task.cancel()
                        group.leave()
                    }
                }

                if every(10) {
                    queue.addOperation {
                        randomSleep()
                        let priority: ImageRequest.Priority = every(2) ? .veryHigh : .veryLow
                        task.priority = priority
                    }
                }
            }
        }

        await withCheckedContinuation { continuation in
            group.notify(queue: .global()) {
                continuation.resume()
            }
        }

        _ = pipeline
    }
}

private func performPipelineThreadSafetyTest(_ pipeline: ImagePipeline) async {
    let group = DispatchGroup()
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 16

    for _ in 0..<1000 {
        group.enter()
        queue.addOperation {
            let url = URL(fileURLWithPath: "\(Int.random(in: 0..<30))")
            let request = ImageRequest(url: url)
            let shouldCancel = Int.random(in: 0..<3) == 0

            let task = pipeline.loadImage(with: request) { _ in
                if shouldCancel {
                    // do nothing, we don't expect completion on cancel
                } else {
                    group.leave()
                }
            }

            if shouldCancel {
                task.cancel()
                group.leave()
            }
        }
    }

    await withCheckedContinuation { continuation in
        group.notify(queue: .global()) {
            continuation.resume()
        }
    }
}

private func _request(index: Int) -> ImageRequest {
    return ImageRequest(url: URL(string: "http://example.com/img\(index)")!)
}

// MARK: - ImageTask Events

/// Serves the data in small chunks, as fast as the pipeline takes them.
private final class ChunkedDataLoader: DataLoading {
    private let data: Data
    private let chunkCount: Int

    init(data: Data, chunkCount: Int) {
        self.data = data
        self.chunkCount = chunkCount
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> Cancellable {
        let response = URLResponse(url: request.url ?? Test.url, mimeType: "jpeg", expectedContentLength: data.count, textEncodingName: nil)
        let data = data
        let chunkSize = data.count / chunkCount + 1
        DispatchQueue.global().async {
            for offset in stride(from: 0, to: data.count, by: chunkSize) {
                didReceiveData(data.subdata(in: offset..<min(offset + chunkSize, data.count)), response)
            }
            completion(nil)
        }
        return NoOpCancellable()
    }
}

private struct NoOpCancellable: Cancellable {
    func cancel() {}
}

/// Creates streams for the task on several threads at once until it finishes.
/// Each thread creates one as soon as it sees the task record new progress –
/// while the pipeline is still sending that event – and one more after the
/// task finishes.
private func makeStreamsOnManyThreads(for task: ImageTask) async -> [EventStream] {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            let streams = OSAllocatedUnfairLock<[EventStream]>(initialState: [])
            DispatchQueue.concurrentPerform(iterations: 8) { _ in
                while true {
                    let status = task.status
                    let stream = EventStream(events: task.events, isFinishedBefore: status.result != nil, isFinishedAfter: task.status.result != nil)
                    streams.withLock { $0.append(stream) }
                    guard !stream.isFinishedBefore else {
                        return
                    }
                    while task.status.result == nil && task.status.progress == status.progress {
                        usleep(10)
                    }
                }
            }
            continuation.resume(returning: streams.withLock { $0 })
        }
    }
}

/// A stream, and whether its task had finished right before and right after
/// the stream was created.
private struct EventStream: Sendable {
    let events: AsyncStream<ImageTask.Event>
    let isFinishedBefore: Bool
    let isFinishedAfter: Bool

    /// Returns `true` if the stream received what it had to, given the events
    /// the task sent.
    ///
    /// A stream created after the task finished replays the terminal event.
    /// Any other stream is registered between two of the events: it starts
    /// with the progress recorded before that point, if any, and receives every
    /// event sent after it, exactly once and in order.
    func isExpected(_ received: [EventKey], sent: [EventKey]) -> Bool {
        let isReplay = received == [.finished]
        guard !isFinishedBefore else {
            return isReplay
        }
        guard !isReplay else {
            return isFinishedAfter
        }
        return sent.indices.contains { index in
            let progress = sent[..<index].last { if case .progress = $0 { true } else { false } }
            return received == (progress.map { [$0] } ?? []) + sent[index...]
        }
    }
}

/// What tells the events of a task apart.
private enum EventKey: Equatable {
    case progress(Int64)
    case preview(ObjectIdentifier)
    case finished

    init(_ event: ImageTask.Event) {
        switch event {
        case .progress(let progress): self = .progress(progress.completed)
        case .preview(let response): self = .preview(ObjectIdentifier(response.image))
        case .finished: self = .finished
        }
    }
}

/// Creates a task and, right away, streams for it on several threads at once
/// until each of them sees the task finish, and one more after that. With
/// `cancels`, one of the threads cancels the task after its first stream.
private func makeStreamsAcrossTheTerminalEvent(of request: ImageRequest, in pipeline: ImagePipeline, cancels: Bool) async -> (ImageTask, [AsyncStream<ImageTask.Event>]) {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            let task = pipeline.imageTask(with: request)
            let streams = OSAllocatedUnfairLock<[AsyncStream<ImageTask.Event>]>(initialState: [])
            DispatchQueue.concurrentPerform(iterations: 8) { thread in
                for iteration in 0..<1000 {
                    let isFinished = task.status.result != nil
                    let stream = task.events
                    streams.withLock { $0.append(stream) }
                    if cancels && thread == 0 && iteration == 0 {
                        task.cancel()
                    }
                    if isFinished {
                        return
                    }
                }
            }
            continuation.resume(returning: (task, streams.withLock { $0 }))
        }
    }
}

/// The name of the event, telling apart only how the task finished.
private func name(of event: ImageTask.Event) -> String {
    switch event {
    case .progress: "progress"
    case .preview: "preview"
    case .finished(.success): "success"
    case .finished(.failure(.cancelled)): "cancelled"
    case .finished(.failure): "failure"
    }
}
