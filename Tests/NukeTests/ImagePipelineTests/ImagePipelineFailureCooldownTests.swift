// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineFailureCooldownTests {
    private let dataLoader = MockDataLoader()
    private let clock = TestClock()

    private func makePipeline(_ configure: (inout ImagePipeline.Configuration) -> Void = { _ in }) -> ImagePipeline {
        ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            var cooldown = ImagePipeline.FailureCooldown(duration: 60)
            cooldown.now = { [clock] in clock.now }
            $0.failureCooldown = cooldown
            configure(&$0)
        }
    }

    private func respond(_ statusCode: Int, to url: URL = Test.url) {
        dataLoader.results[url] = .failure(DataLoader.Error.statusCodeUnacceptable(statusCode) as NSError)
    }

    // MARK: - The Window

    @Test func loadWithinTheWindowMakesNoRequest() async {
        // Given
        let pipeline = makePipeline()
        respond(404)
        #expect(await pipeline.failure(of: Test.request)?.isCooldown == false)

        // When
        clock.advance(by: 59)
        let error = await pipeline.failure(of: Test.request)

        // Then
        #expect(error?.isCooldown == true)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func loadAfterTheWindowMakesARequest() async {
        // Given
        let pipeline = makePipeline()
        respond(404)
        _ = await pipeline.failure(of: Test.request)

        // When
        clock.advance(by: 60)
        let error = await pipeline.failure(of: Test.request)

        // Then the server gets to answer again
        #expect(error?.isCooldown == false)
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func aFailureAfterTheWindowStartsANewOne() async {
        // Given
        let pipeline = makePipeline()
        respond(404)
        _ = await pipeline.failure(of: Test.request)
        clock.advance(by: 60)
        _ = await pipeline.failure(of: Test.request)

        // When
        clock.advance(by: 59)
        let error = await pipeline.failure(of: Test.request)

        // Then
        #expect(error?.isCooldown == true)
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func isOffByDefault() async {
        // Given
        #expect(ImagePipeline.Configuration().failureCooldown == nil)
        let pipeline = makePipeline { $0.failureCooldown = nil }
        respond(404)

        // When
        _ = await pipeline.failure(of: Test.request)
        let error = await pipeline.failure(of: Test.request)

        // Then
        #expect(error?.isCooldown == false)
        #expect(dataLoader.createdTaskCount == 2)
    }

    // MARK: - What Counts

    @Test(arguments: [404, 410]) func statusCodesThatSayTheImageIsGone(statusCode: Int) async {
        // Given
        let pipeline = makePipeline()
        respond(statusCode)
        _ = await pipeline.failure(of: Test.request)

        // When
        let error = await pipeline.failure(of: Test.request)

        // Then
        #expect(error?.isCooldown == true)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test(arguments: [400, 401, 403, 408, 429, 500, 502, 503, 504])
    func statusCodesThatSayNothingAboutTheURL(statusCode: Int) async {
        // Given
        let pipeline = makePipeline()
        respond(statusCode)
        _ = await pipeline.failure(of: Test.request)

        // When
        let error = await pipeline.failure(of: Test.request)

        // Then
        #expect(error?.isCooldown == false)
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost, .networkConnectionLost])
    func connectionFailuresDoNotCount(code: URLError.Code) async {
        // Given
        let pipeline = makePipeline()
        dataLoader.results[Test.url] = .failure(URLError(code) as NSError)
        _ = await pipeline.failure(of: Test.request)

        // When
        _ = await pipeline.failure(of: Test.request)

        // Then
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func customStatusCodes() async {
        // Given
        let pipeline = makePipeline { $0.failureCooldown?.statusCodes = [500] }
        respond(500)
        _ = await pipeline.failure(of: Test.request)
        respond(404, to: otherURL)
        _ = await pipeline.failure(of: ImageRequest(url: otherURL))

        // When
        let cooled = await pipeline.failure(of: Test.request)
        let other = await pipeline.failure(of: ImageRequest(url: otherURL))

        // Then
        #expect(cooled?.isCooldown == true)
        #expect(other?.isCooldown == false)
    }

    @Test func aFailureToDecodeDoesNotCount() async {
        // Given a 200 with something that isn't an image
        let pipeline = makePipeline()
        let response = HTTPURLResponse(url: Test.url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        dataLoader.results[Test.url] = .success((Data([1, 2, 3]), response))
        _ = await pipeline.failure(of: Test.request)

        // When
        _ = await pipeline.failure(of: Test.request)

        // Then
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func aCancelledLoadDoesNotCount() async {
        // Given
        let pipeline = makePipeline()
        respond(404)
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)
        await pipeline.waitForTaskCount(1)
        task.cancel()
        _ = await task.outcome
        dataLoader.isSuspended = false

        // When
        let error = await pipeline.failure(of: Test.request)

        // Then
        #expect(error?.isCooldown == false)
    }

    @Test func aClosureThatThrowsTheSameErrorDoesNotCount() async {
        // Given
        let pipeline = makePipeline()
        let count = OSAllocatedUnfairLock(initialState: 0)
        let request = ImageRequest(id: "closure", data: {
            count.withLock { $0 += 1 }
            throw DataLoader.Error.statusCodeUnacceptable(404)
        })

        // When
        _ = await pipeline.failure(of: request)
        let error = await pipeline.failure(of: request)

        // Then the cooldown is about URLs, and an app can do what it wants in its closure
        #expect(error?.isCooldown == false)
        #expect(count.withLock { $0 } == 2)
    }

    @Test func worksWithDataLoader() async throws {
        // Given a real response going through the default validation
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let count = OSAllocatedUnfairLock(initialState: 0)
        let url = StubURLProtocol.register {
            count.withLock { $0 += 1 }
            $0.respond(statusCode: 404, chunks: [Test.data])
        }
        let pipeline = makePipeline { $0.dataLoader = DataLoader(configuration: configuration) }

        // When
        let first = await pipeline.failure(of: ImageRequest(url: url))
        let second = await pipeline.failure(of: ImageRequest(url: url))

        // Then
        #expect(first?.isCooldown == false)
        #expect(second?.isCooldown == true)
        #expect(count.withLock { $0 } == 1)
    }

    // MARK: - Caches

    @Test func imageInDiskCacheIsServedDuringTheCooldown() async throws {
        // Given
        let dataCache = MockDataCache()
        let pipeline = makePipeline { $0.dataCache = dataCache }
        respond(404)
        _ = await pipeline.failure(of: Test.request)

        // When the image gets into the cache some other way
        pipeline.cache.storeCachedData(Test.data, for: Test.request)
        let response = try await pipeline.imageTask(with: Test.request).response

        // Then
        #expect(response.cacheType == .disk)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func imageInMemoryCacheIsServedDuringTheCooldown() async throws {
        // Given
        let pipeline = makePipeline { $0.imageCache = MockImageCache() }
        respond(404)
        _ = await pipeline.failure(of: Test.request)

        // When
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)
        let response = try await pipeline.imageTask(with: Test.request).response

        // Then
        #expect(response.cacheType == .memory)
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Getting Around It

    @Test(arguments: [ImageRequest.Options.skipFailureCooldown, .reloadIgnoringCachedData])
    func optionsThatReachTheNetwork(options: ImageRequest.Options) async {
        // Given
        let pipeline = makePipeline()
        respond(404)
        _ = await pipeline.failure(of: Test.request)

        // When
        let error = await pipeline.failure(of: ImageRequest(url: Test.url, options: options))

        // Then
        #expect(error?.isCooldown == false)
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func anOptionThatOnlyDisablesOneCacheDoesNot() async {
        // Given
        let pipeline = makePipeline()
        respond(404)
        _ = await pipeline.failure(of: Test.request)

        // When
        let error = await pipeline.failure(of: ImageRequest(url: Test.url, options: [.disableDiskCacheReads]))

        // Then
        #expect(error?.isCooldown == true)
    }

    @Test func aSuccessEndsTheCooldown() async {
        // Given
        let pipeline = makePipeline()
        respond(404)
        _ = await pipeline.failure(of: Test.request)

        // When the image is back
        dataLoader.results[Test.url] = nil
        let retry = await pipeline.failure(of: ImageRequest(url: Test.url, options: .skipFailureCooldown))
        let next = await pipeline.failure(of: Test.request)

        // Then
        #expect(retry == nil)
        #expect(next == nil)
        #expect(dataLoader.createdTaskCount == 3)
    }

    @Test func aFailedRetryExtendsTheCooldown() async {
        // Given
        let pipeline = makePipeline()
        respond(404)
        _ = await pipeline.failure(of: Test.request)

        // When
        clock.advance(by: 50)
        _ = await pipeline.failure(of: ImageRequest(url: Test.url, options: .skipFailureCooldown))
        clock.advance(by: 50)
        let error = await pipeline.failure(of: Test.request)

        // Then the window restarted with the retry
        #expect(error?.isCooldown == true)
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func resetEndsTheCooldownOfEveryURL() async {
        // Given
        let pipeline = makePipeline()
        let other = otherURL
        respond(404)
        respond(410, to: other)
        _ = await pipeline.failure(of: Test.request)
        _ = await pipeline.failure(of: ImageRequest(url: other))

        // When
        await pipeline.resetFailureCooldown()
        _ = await pipeline.failure(of: Test.request)
        _ = await pipeline.failure(of: ImageRequest(url: other))

        // Then
        #expect(dataLoader.createdTaskCount == 4)
    }

    // MARK: - Scope

    @Test func pipelinesDoNotShareTheirCooldowns() async {
        // Given
        let first = makePipeline()
        let second = makePipeline()
        respond(404)
        _ = await first.failure(of: Test.request)

        // When
        let error = await second.failure(of: Test.request)

        // Then
        #expect(error?.isCooldown == false)
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func aCooldownCoversEveryRequestForTheURL() async {
        // Given
        let pipeline = makePipeline()
        respond(404)
        _ = await pipeline.failure(of: Test.request)

        var withImageID = Test.request
        withImageID.imageID = "custom"
        var withThumbnail = Test.request
        withThumbnail.thumbnail = .init(maxPixelSize: 100)

        // When
        let requests = [
            withImageID,
            withThumbnail,
            ImageRequest(url: Test.url, processors: [.resize(width: 100)]),
            ImageRequest(url: Test.url, options: .skipDataLoadingQueue),
            ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadIgnoringLocalCacheData))
        ]
        for request in requests {
            let error = await pipeline.failure(of: request)
            #expect(error?.isCooldown == true)
        }

        // Then
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func aCustomImageIDDoesNotSpreadTheCooldown() async {
        // Given two URLs with one image ID
        let pipeline = makePipeline()
        var request = Test.request
        request.imageID = "custom"
        respond(404)
        _ = await pipeline.failure(of: request)

        // When
        var other = ImageRequest(url: otherURL)
        other.imageID = "custom"
        let error = await pipeline.failure(of: other)

        // Then
        #expect(error == nil)
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func dataTasksRespectIt() async {
        // Given
        let pipeline = makePipeline()
        respond(404)
        _ = await pipeline.failure(of: Test.request)

        // When
        do {
            _ = try await pipeline.data(for: Test.request)
            Issue.record("Expected the load to fail")
        } catch {
            #expect(error.isCooldown)
        }

        // Then
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func prefetchingRespectsIt() async {
        // Given
        let pipeline = makePipeline()
        respond(404)
        _ = await pipeline.failure(of: Test.request)

        // When
        let prefetcher = ImagePrefetcher(pipeline: pipeline)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            prefetcher.didComplete = { @Sendable in continuation.resume() }
            prefetcher.startPrefetching(with: [Test.url])
        }

        // Then
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func aURLInCooldownDoesNotWaitForTheQueue() async {
        // Given
        let queue = TaskQueue(maxConcurrentTaskCount: 1)
        let pipeline = makePipeline { $0.dataLoadingQueue = queue }
        respond(404)
        _ = await pipeline.failure(of: Test.request)

        // When nothing can get a slot
        queue.isSuspended = true
        let error = await pipeline.failure(of: Test.request)

        // Then
        #expect(error?.isCooldown == true)
    }

    @Test func coalescedTasksShareTheDownloadAndTheFailure() async {
        // Given
        let pipeline = makePipeline()
        respond(404)
        dataLoader.isSuspended = true
        let first = pipeline.imageTask(with: Test.request)
        let second = pipeline.imageTask(with: Test.request)
        await pipeline.waitForTaskCount(2)

        // When
        dataLoader.isSuspended = false
        let results = [await first.outcome, await second.outcome]
        let next = await pipeline.failure(of: Test.request)

        // Then
        #expect(results.allSatisfy { if case .failure(.dataLoadingFailed) = $0 { true } else { false } })
        #expect(next?.isCooldown == true)
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Reporting

    @Test func errorSaysWhatHappened() async throws {
        // Given
        let pipeline = makePipeline()
        respond(404)
        _ = await pipeline.failure(of: Test.request)

        // When
        let error = try #require(await pipeline.failure(of: Test.request))

        // Then the status code is where the code that handles the failure looks for it
        guard case .statusCodeUnacceptable(404)? = error.dataLoadingError as? DataLoader.Error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
        #expect(error.description == "Didn't request the URL because it failed recently and is in cooldown. Underlying error: Response status code was unacceptable: 404.")
    }

    @Test func metricsShowThatTheDownloadNeverStarted() async throws {
        // Given
        let pipeline = makePipeline { $0.isDiagnosticsEnabled = true }
        respond(404)
        _ = await pipeline.failure(of: Test.request)

        // When
        let task = pipeline.imageTask(with: Test.request)
        _ = await task.outcome

        // Then
        let metrics = try #require(task.metrics)
        #expect(metrics.error?.code == "urlInCooldown")
        #expect(metrics.error?.underlyingDomain != nil)
        let download = try #require(metrics.jobs.last?.stages.first { $0.kind == .download })
        #expect(download.source == .failureCooldown)
        #expect(download.bytes == nil)
    }

    // MARK: - Registry

    @Test @ImagePipelineActor func registryIsBounded() {
        // Given a full registry
        let (registry, clock) = makeRegistry()
        for index in 0..<FailureRegistry.countLimit {
            clock.advance(by: 0.001)
            registry.didFinishLoading(makeRequest(index), error: notFound)
        }
        #expect(registry.count == FailureRegistry.countLimit)

        // When
        clock.advance(by: 0.001)
        registry.didFinishLoading(makeRequest(FailureRegistry.countLimit), error: notFound)

        // Then the one that would have expired first made room
        #expect(registry.count == FailureRegistry.countLimit)
        #expect(registry.failure(for: makeRequest(0)) == nil)
        #expect(registry.failure(for: makeRequest(1)) != nil)
        #expect(registry.failure(for: makeRequest(FailureRegistry.countLimit)) != nil)
    }

    @Test @ImagePipelineActor func aFullRegistryDropsWhatExpiredFirst() {
        // Given a full registry with nothing left of the window
        let (registry, clock) = makeRegistry()
        for index in 0..<FailureRegistry.countLimit {
            registry.didFinishLoading(makeRequest(index), error: notFound)
        }

        // When
        clock.advance(by: 61)
        registry.didFinishLoading(makeRequest(FailureRegistry.countLimit), error: notFound)

        // Then
        #expect(registry.count == 1)
    }

    @Test @ImagePipelineActor func aURLAlreadyInAFullRegistryPushesNothingOut() {
        // Given
        let (registry, _) = makeRegistry()
        for index in 0..<FailureRegistry.countLimit {
            registry.didFinishLoading(makeRequest(index), error: notFound)
        }

        // When
        registry.didFinishLoading(makeRequest(5), error: notFound)

        // Then
        #expect(registry.count == FailureRegistry.countLimit)
        #expect(registry.failure(for: makeRequest(0)) != nil)
    }

    @Test @ImagePipelineActor func anExpiredEntryIsDroppedWhenItIsLookedUp() {
        // Given
        let (registry, clock) = makeRegistry()
        registry.didFinishLoading(makeRequest(0), error: notFound)
        clock.advance(by: 30)
        registry.didFinishLoading(makeRequest(1), error: notFound)

        // When
        clock.advance(by: 30)

        // Then
        #expect(registry.failure(for: makeRequest(0)) == nil)
        #expect(registry.count == 1)
    }

    private var notFound: ImagePipeline.Error {
        .dataLoadingFailed(error: DataLoader.Error.statusCodeUnacceptable(404))
    }

    private func makeRequest(_ index: Int) -> ImageRequest {
        ImageRequest(url: URL(string: "https://example.com/\(index).jpeg"))
    }

    private func makeRegistry() -> (FailureRegistry, TestClock) {
        let clock = TestClock()
        var cooldown = ImagePipeline.FailureCooldown(duration: 60)
        cooldown.now = { clock.now }
        return (FailureRegistry(cooldown: cooldown), clock)
    }
}

private let otherURL = URL(string: "http://test.com/other.jpeg")!

private final class TestClock: Sendable {
    private let time = OSAllocatedUnfairLock<TimeInterval>(initialState: 1000)

    var now: TimeInterval { time.withLock { $0 } }

    func advance(by interval: TimeInterval) {
        time.withLock { $0 += interval }
    }
}

private extension ImagePipeline {
    /// Loads the request, and returns the error it fails with.
    nonisolated func failure(of request: ImageRequest) async -> ImagePipeline.Error? {
        if case .failure(let error) = await imageTask(with: request).outcome {
            return error
        }
        return nil
    }

    func waitForTaskCount(_ count: Int) async {
        while taskCount < count {
            await Task.yield()
        }
    }
}

private extension ImageTask {
    var outcome: Result<ImageResponse, ImagePipeline.Error> {
        get async {
            do {
                return .success(try await response)
            } catch {
                return .failure(error)
            }
        }
    }
}

private extension ImagePipeline.Error {
    var isCooldown: Bool {
        if case .urlInCooldown = self { true } else { false }
    }
}
