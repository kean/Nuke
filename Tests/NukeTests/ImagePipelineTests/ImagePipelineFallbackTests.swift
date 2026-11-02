// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

/// `ImageRequest/alternatives` and `ImageRequest/lowDataURL`: what an image task
/// does when its source fails, and what that leaves in the caches.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineFallbackTests {
    private let dataLoader: MockDataLoader
    private let imageCache: MockImageCache
    private let dataCache: MockDataCache
    private let pipeline: ImagePipeline

    private let primaryURL = Test.url
    private let mirrorURL = URL(string: "http://test.com/mirror.jpeg")!
    private let otherMirrorURL = URL(string: "http://test.com/other-mirror.jpeg")!
    private let lowDataURL = URL(string: "http://test.com/low-data.jpeg")!

    private let failure = Result<(Data, URLResponse), NSError>.failure(NSError(domain: "Test", code: 500))
    /// What `URLSession` fails with on a network in Low Data Mode.
    private let constrained = Result<(Data, URLResponse), NSError>.failure(NSError(
        domain: NSURLErrorDomain,
        code: URLError.notConnectedToInternet.rawValue,
        userInfo: [NSURLErrorNetworkUnavailableReasonKey: URLError.NetworkUnavailableReason.constrained.rawValue]
    ))

    init() {
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        let dataCache = MockDataCache()
        self.dataLoader = dataLoader
        self.imageCache = imageCache
        self.dataCache = dataCache
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
            $0.isDiagnosticsEnabled = true
        }
    }

    private func request(_ alternatives: URL...) -> ImageRequest {
        ImageRequest(url: primaryURL).with { $0.alternatives = alternatives.map(ImageSource.url) }
    }

    /// A request whose source fails after a hop, with the data loader free to
    /// hold on to the alternatives.
    private func failingRequest(_ alternatives: URL...) -> ImageRequest {
        ImageRequest(id: "failing", data: { throw URLError(.badServerResponse) }).with {
            $0.alternatives = alternatives.map(ImageSource.url)
        }
    }

    private func result(of task: ImageTask) async -> Result<ImageResponse, ImagePipeline.Error> {
        do {
            return .success(try await task.response)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Moving On

    @Test func sourcesAreTriedInOrderUntilOneLoads() async throws {
        // GIVEN a request whose source and first alternative fail
        dataLoader.results[primaryURL] = failure
        dataLoader.results[mirrorURL] = failure

        // WHEN
        let task = pipeline.imageTask(with: request(mirrorURL, otherMirrorURL))
        let response = try await task.response

        // THEN each is requested once, in order, and no further
        #expect(dataLoader.requestedURLs == [primaryURL, mirrorURL, otherMirrorURL])
        // AND the response says what was loaded, and the task what was asked for
        #expect(response.request.url == otherMirrorURL)
        #expect(task.request.url == primaryURL)
    }

    @Test func alternativesAreNotUsedWhenTheSourceLoads() async throws {
        let response = try await pipeline.imageTask(with: request(mirrorURL)).response

        #expect(dataLoader.requestedURLs == [primaryURL])
        #expect(response.request.url == primaryURL)
    }

    @Test func taskFinishesOnce() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure

        // WHEN
        var finished = 0
        for await event in pipeline.imageTask(with: request(mirrorURL)).events {
            if case .finished(.success) = event {
                finished += 1
            } else if case .finished(.failure) = event {
                Issue.record("A failed source isn't the end of the task")
            }
        }

        // THEN
        #expect(finished == 1)
    }

    @Test func taskFailsWithTheErrorOfItsOwnSource() async throws {
        // GIVEN every source fails, each differently
        dataLoader.results[primaryURL] = failure
        dataLoader.results[mirrorURL] = .failure(NSError(domain: "Test", code: 404))

        // WHEN
        let task = pipeline.imageTask(with: request(mirrorURL))
        let result = await result(of: task)

        // THEN
        #expect(dataLoader.requestedURLs == [primaryURL, mirrorURL])
        guard case let .failure(.dataLoadingFailed(error)) = result else {
            Issue.record("Expected a failure, got \(result)")
            return
        }
        #expect((error as NSError).code == 500)
    }

    @Test func sourcesCanBeOfEveryKind() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure
        dataLoader.results[mirrorURL] = failure
        let data = Test.data
        let image = Test.container

        // WHEN the alternatives are, in turn, a `URLRequest`, a fetch of data
        // that fails, a fetch of data, and a fetch of an image
        var urlRequest = URLRequest(url: mirrorURL)
        urlRequest.setValue("token", forHTTPHeaderField: "X-Token")
        let first = try await pipeline.imageTask(with: ImageRequest(url: primaryURL).with {
            $0.alternatives = [
                .urlRequest(urlRequest),
                .data(id: "failing") { throw URLError(.badServerResponse) },
                .data(id: "data") { data }
            ]
        }).response
        #expect(dataLoader.requests.last?.value(forHTTPHeaderField: "X-Token") == "token")
        #expect(first.request.imageID == "data")

        let second = try await pipeline.imageTask(with: ImageRequest(url: mirrorURL).with {
            $0.alternatives = [.image(id: "placeholder") { image }]
        }).response
        #expect(second.request.imageID == "placeholder")
    }

    @Test func requestWithoutURLMovesOnToItsAlternatives() async throws {
        let request = ImageRequest(url: nil).with { $0.alternatives = [.url(mirrorURL)] }

        let response = try await pipeline.imageTask(with: request).response

        #expect(dataLoader.requestedURLs == [mirrorURL])
        #expect(response.request.url == mirrorURL)
    }

    @Test func dataTaskMovesOnToItsAlternatives() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure

        // WHEN
        let (data, _) = try await pipeline.data(for: request(mirrorURL))

        // THEN
        #expect(!data.isEmpty)
        #expect(dataLoader.requestedURLs == [primaryURL, mirrorURL])
        #expect(dataCache.store[mirrorURL.absoluteString] != nil)
        #expect(dataCache.store[primaryURL.absoluteString] == nil)
    }

    // MARK: - The Caches

    @Test func fallbackIsCachedUnderItsOwnKeys() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure

        // WHEN
        let request = request(mirrorURL)
        _ = try await pipeline.imageTask(with: request).response

        // THEN the fallback's bytes are under its key, and nothing is under the
        // key of the source that failed
        #expect(dataCache.store.keys.sorted() == [mirrorURL.absoluteString])
        #expect(imageCache.images.count == 1)
        #expect(pipeline.cache[ImageRequest(url: mirrorURL)] != nil)
        #expect(pipeline.cache[request] == nil)
        #expect(!pipeline.cache.containsCachedImage(for: request))
    }

    @Test func laterLoadsTryTheSourceAgain() async throws {
        // GIVEN a source that failed and an alternative that loaded
        dataLoader.results[primaryURL] = failure
        let request = request(mirrorURL)
        _ = try await pipeline.imageTask(with: request).response
        #expect(dataLoader.requestedURLs == [primaryURL, mirrorURL])

        // WHEN it's loaded again
        let second = try await pipeline.imageTask(with: request).response

        // THEN the source is requested, and the alternative comes from the cache
        #expect(dataLoader.requestedURLs == [primaryURL, mirrorURL, primaryURL])
        #expect(second.cacheType == .memory)
        #expect(second.request.url == mirrorURL)

        // WHEN the source is back
        dataLoader.results[primaryURL] = nil
        let third = try await pipeline.imageTask(with: request).response

        // THEN it wins, and it's what the next load finds
        #expect(dataLoader.requestedURLs == [primaryURL, mirrorURL, primaryURL, primaryURL])
        #expect(third.request.url == primaryURL)
        #expect(dataCache.store[primaryURL.absoluteString] != nil)
    }

    @Test func customImageIDStaysWithTheSource() async throws {
        // GIVEN a request with a custom ID, which is what the caches key it by
        dataLoader.results[primaryURL] = failure
        let request = request(mirrorURL).with { $0.imageID = "custom" }

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN the alternative doesn't take over its entries
        #expect(response.request.imageID == mirrorURL.absoluteString)
        #expect(dataCache.store["custom"] == nil)
        #expect(pipeline.cache[request] == nil)
    }

    @Test func requestKeepsItsCacheOptionsOnTheFallback() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure
        let request = request(mirrorURL).with { $0.options = [.disableDiskCacheWrites, .disableMemoryCacheWrites] }

        // WHEN
        _ = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(dataCache.store.isEmpty)
        #expect(imageCache.images.isEmpty)
    }

    // MARK: - What the Fallback Inherits

    @Test func fallbackIsProcessedLikeTheSource() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure
        let request = request(mirrorURL).with {
            $0.processors = [MockImageProcessor(id: "1")]
            $0.scale = 2
            $0.userInfo["key"] = "value"
        }

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.nk_test_processorIDs == ["1"])
        #expect(response.request.scale == 2)
        #expect(response.request.userInfo["key"] as? String == "value")
        // AND it's under the key of the processed alternative
        #expect(pipeline.cache[ImageRequest(url: mirrorURL, processors: [MockImageProcessor(id: "1")]).with { $0.scale = 2 }] != nil)
    }

    @Test func fallbackHasNoFallbacksOfItsOwn() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure

        // WHEN
        let request = request(mirrorURL).with { $0.lowDataURL = lowDataURL }
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.request.alternatives.isEmpty)
        #expect(response.request.lowDataURL == nil)
        #expect(response.request.urlRequest?.allowsConstrainedNetworkAccess == true)
    }

    @Test @ImagePipelineActor func fallbackRunsAtThePriorityOfTheTask() async throws {
        // GIVEN a task that failed over while its priority was raised
        dataLoader.results[primaryURL] = failure
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        var task: ImageTask?
        let operations = await queue.waitForOperations(count: 1) {
            task = pipeline.imageTask(with: request(mirrorURL))
        }
        let operation = try #require(operations.first)
        await waitForPriorityChange(of: operation, to: .high) {
            task?.priority = .high
        }

        // WHEN
        let next = await queue.waitForOperations(count: 1) {
            queue.isSuspended = false
        }

        // THEN the fallback's download has it
        #expect(next.first?.priority == .high)
        _ = try await task?.response
    }

    // MARK: - What Fails Over

    @Test func emptyResponseMovesOn() async throws {
        dataLoader.results[primaryURL] = .success((Data(), URLResponse(url: primaryURL, mimeType: "jpeg", expectedContentLength: 0, textEncodingName: nil)))

        let response = try await pipeline.imageTask(with: request(mirrorURL)).response

        #expect(response.request.url == mirrorURL)
    }

    @Test func dataThatCantBeDecodedMovesOn() async throws {
        // GIVEN a server that sends back a page and a `200`
        dataLoader.results[primaryURL] = .success((Data("<html></html>".utf8), Test.urlResponse))

        // WHEN
        let response = try await pipeline.imageTask(with: request(mirrorURL)).response

        // THEN
        #expect(response.request.url == mirrorURL)
    }

    @Test func downloadOverTheLimitMovesOn() async throws {
        // GIVEN a limit that the source exceeds and the alternative doesn't
        let pipeline = pipeline.reconfigured { $0.maximumResponseDataSize = Test.data.count * 2 }
        dataLoader.results[primaryURL] = .success((Data(count: Test.data.count * 4), Test.urlResponse))

        // WHEN
        let response = try await pipeline.imageTask(with: request(mirrorURL)).response

        // THEN
        #expect(dataLoader.requestedURLs == [primaryURL, mirrorURL])
        #expect(response.request.url == mirrorURL)
    }

    @Test func requestThatMustNotLoadDoesntMoveOn() async throws {
        // GIVEN
        let request = request(mirrorURL).with { $0.options = [.returnCacheDataDontLoad] }

        // WHEN
        let result = await result(of: pipeline.imageTask(with: request))

        // THEN
        guard case .failure(.dataMissingInCache) = result else {
            Issue.record("Expected dataMissingInCache, got \(result)")
            return
        }
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func processorThatFailsDoesntMoveOn() async throws {
        // GIVEN a failure that every source would repeat
        let request = request(mirrorURL).with { $0.processors = [MockFailingProcessor()] }

        // WHEN
        let result = await result(of: pipeline.imageTask(with: request))

        // THEN
        guard case .failure(.processingFailed) = result else {
            Issue.record("Expected processingFailed, got \(result)")
            return
        }
        #expect(dataLoader.requestedURLs == [primaryURL])
    }

    @Test func dataLoaderCancellationDoesntMoveOn() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = .failure(NSError(domain: NSURLErrorDomain, code: URLError.cancelled.rawValue))

        // WHEN
        _ = await result(of: pipeline.imageTask(with: request(mirrorURL)))

        // THEN
        #expect(dataLoader.requestedURLs == [primaryURL])
    }

    // MARK: - Cancellation

    @Test func cancellingTheTaskCancelsTheFallback() async throws {
        // GIVEN a task waiting for its alternative
        dataLoader.isSuspended = true
        let didStart = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.imageTask(with: failingRequest(mirrorURL))
        await didStart.wait()

        // WHEN
        let didCancel = TestExpectation(notification: MockDataLoader.DidCancelTask, object: dataLoader)
        task.cancel()

        // THEN
        await didCancel.wait()
        guard case .failure(.cancelled) = await result(of: task) else {
            Issue.record("Expected a cancelled task")
            return
        }
    }

    @Test func cancellingATaskWhoseSourceFailedRightAwayCancelsTheFallback() async throws {
        // GIVEN a source that fails from inside `subscribe`, before the pipeline
        // has stored the subscription it's about to replace
        dataLoader.isSuspended = true
        let didStart = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.imageTask(with: ImageRequest(url: nil).with { $0.alternatives = [.url(mirrorURL)] })
        await didStart.wait()

        // WHEN
        let didCancel = TestExpectation(notification: MockDataLoader.DidCancelTask, object: dataLoader)
        task.cancel()

        // THEN
        await didCancel.wait()
    }

    @Test func invalidatingThePipelineStopsTheFallback() async throws {
        // GIVEN a task waiting for its first alternative
        dataLoader.isSuspended = true
        let didStart = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.imageTask(with: failingRequest(mirrorURL, otherMirrorURL))
        await didStart.wait()

        // WHEN
        pipeline.invalidate()

        // THEN it goes no further
        guard case .failure(.cancelled) = await result(of: task) else {
            Issue.record("Expected a cancelled task")
            return
        }
        #expect(dataLoader.requestedURLs == [mirrorURL])
    }

    // MARK: - Coalescing

    @Test func tasksShareTheSourceAndWalkTheirOwnAlternatives() async throws {
        // GIVEN two tasks for one image with different alternatives
        dataLoader.results[primaryURL] = failure

        // WHEN
        let (first, second) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) { [pipeline] in
            (pipeline.imageTask(with: request(mirrorURL)), pipeline.imageTask(with: request(otherMirrorURL)))
        }
        let firstResponse = try await first.response
        let secondResponse = try await second.response

        // THEN the source is loaded once, and each gets the alternative it asked for
        #expect(dataLoader.requestedURLs.filter { $0 == primaryURL }.count == 1)
        #expect(dataLoader.requestedURLs.count == 3)
        #expect(firstResponse.request.url == mirrorURL)
        #expect(secondResponse.request.url == otherMirrorURL)
    }

    @Test func tasksShareTheAlternativeToo() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure
        dataLoader.results[mirrorURL] = .success((Test.data, Test.urlResponse))

        // WHEN
        let (first, second) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) { [pipeline] in
            (pipeline.imageTask(with: request(mirrorURL)), pipeline.imageTask(with: request(mirrorURL)))
        }
        _ = try await first.response
        _ = try await second.response

        // THEN
        #expect(dataLoader.requestedURLs.count == 2)
    }

    @Test func taskWithoutAlternativesFailsWhileTheOneItSharesWithMovesOn() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure

        // WHEN
        let (first, second) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) { [pipeline] in
            (pipeline.imageTask(with: ImageRequest(url: primaryURL)), pipeline.imageTask(with: request(mirrorURL)))
        }
        let firstResult = await result(of: first)
        let secondResult = await result(of: second)

        // THEN
        #expect((try? firstResult.get()) == nil)
        #expect((try? secondResult.get()) != nil)
    }

    @Test func alternativesAreNotInTheKeys() {
        let plain = ImageRequest(url: primaryURL)
        let other = request(mirrorURL)

        #expect(TaskLoadImageKey(plain) == TaskLoadImageKey(other))
        #expect(TaskFetchOriginalImageKey(plain) == TaskFetchOriginalImageKey(other))
        #expect(TaskFetchOriginalDataKey(plain) == TaskFetchOriginalDataKey(other))
        #expect(MemoryCacheKey(plain) == MemoryCacheKey(other))
    }

    // MARK: - Prefetching

    @Test func prefetchingFollowsTheAlternatives() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure
        let prefetcher = ImagePrefetcher(pipeline: pipeline)
        let didComplete = TestExpectation()
        prefetcher.didComplete = { didComplete.fulfill() }

        // WHEN
        prefetcher.startPrefetching(with: [request(mirrorURL)])
        await didComplete.wait()

        // THEN
        #expect(dataLoader.requestedURLs == [primaryURL, mirrorURL])
        #expect(pipeline.cache[ImageRequest(url: mirrorURL)] != nil)
    }

    // MARK: - Diagnostics

    @Test func metricsShowTheFallback() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure
        dataLoader.results[otherMirrorURL] = .success((Test.data, Test.urlResponse))
        dataLoader.results[mirrorURL] = failure

        // WHEN
        let task = pipeline.imageTask(with: request(mirrorURL, otherMirrorURL))
        _ = try await task.response

        // THEN the record has each move, and the error that caused it
        let metrics = try #require(task.metrics)
        let fallbacks = try #require(metrics.fallbacks)
        #expect(fallbacks.map(\.url) == [mirrorURL.absoluteString, otherMirrorURL.absoluteString])
        #expect(fallbacks.map(\.error.code) == ["dataLoadingFailed", "dataLoadingFailed"])
        #expect(fallbacks[0].at >= metrics.createdAt && fallbacks[0].at <= fallbacks[1].at)

        // AND the request and the outcome are of the task
        #expect(metrics.request.url == primaryURL.absoluteString)
        #expect(metrics.outcome == .success)
        #expect(metrics.error == nil)

        // AND the jobs are of all three sources, in order, with the failures
        let roots = metrics.jobs.filter { $0.kind == .loadImage }
        #expect(roots.count == 3)
        #expect(roots.map(\.outcome) == [.failure, .failure, .success])
        #expect(metrics.rootJobID == roots.last?.id)
    }

    @Test func metricsOfTheResultComeFromTheLastSource() async throws {
        // GIVEN a source that sends a body before it turns out to be broken,
        // and an alternative already in the memory cache
        dataLoader.results[primaryURL] = .success((Data("<html></html>".utf8), Test.urlResponse))
        pipeline.cache[ImageRequest(url: mirrorURL)] = Test.container

        // WHEN
        let task = pipeline.imageTask(with: request(mirrorURL))
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.source == .memory)
        #expect(metrics.bytes == nil)
    }

    @Test func metricsOfATaskThatRanOutOfSources() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure
        dataLoader.results[mirrorURL] = .failure(NSError(domain: "Test", code: 404))

        // WHEN
        let task = pipeline.imageTask(with: request(mirrorURL))
        _ = await result(of: task)

        // THEN
        let metrics = try #require(task.metrics)
        #expect(metrics.outcome == .failure)
        #expect(metrics.fallbacks?.count == 1)
        #expect(metrics.source == nil)
    }

    @Test func metricsOfATaskThatDidntFallBack() async throws {
        let task = pipeline.imageTask(with: request(mirrorURL))
        _ = try await task.response

        #expect(try #require(task.metrics).fallbacks == nil)
    }

    @Test func recordsPrintTheFallback() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure

        // WHEN
        let task = pipeline.imageTask(with: request(mirrorURL))
        _ = try await task.response
        let metrics = try #require(task.metrics)

        // THEN
        #expect(metrics.summary.contains("1 fallback"))
        let report = metrics.formatted(.plain)
        #expect(report.contains("fallback:"))
        #expect(report.contains(mirrorURL.absoluteString))
        #expect(report.contains("dataLoadingFailed"))
    }

    @Test func recordWithAFallbackRoundTrips() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure
        let task = pipeline.imageTask(with: request(mirrorURL))
        _ = try await task.response
        let metrics = try #require(task.metrics)

        // WHEN
        let decoded = try JSONDecoder().decode(ImageTask.Metrics.self, from: JSONEncoder().encode(metrics))

        // THEN
        #expect(decoded.fallbacks?.first?.url == mirrorURL.absoluteString)
        #expect(decoded.fallbacks?.first?.imageID == mirrorURL.absoluteString)
        #expect(decoded.fallbacks?.first?.error.code == "dataLoadingFailed")
    }

    // MARK: - Low Data Mode

    @Test func requestWithLowDataURLStaysOffConstrainedNetworks() async throws {
        // WHEN
        let request = ImageRequest(url: primaryURL).with { $0.lowDataURL = lowDataURL }
        _ = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(dataLoader.requests.map(\.allowsConstrainedNetworkAccess) == [false])
    }

    @Test func requestWithoutLowDataURLIsLeftAlone() async throws {
        _ = try await pipeline.imageTask(with: request(mirrorURL)).response

        #expect(dataLoader.requests.map(\.allowsConstrainedNetworkAccess) == [true])
    }

    @Test func lowDataURLIsLoadedWhenTheNetworkIsConstrained() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = constrained
        let request = ImageRequest(url: primaryURL).with { $0.lowDataURL = lowDataURL }

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN it goes out with constrained access, which is the point of it
        #expect(dataLoader.requestedURLs == [primaryURL, lowDataURL])
        #expect(dataLoader.requests.map(\.allowsConstrainedNetworkAccess) == [false, true])
        #expect(response.request.url == lowDataURL)
        // AND it's cached as itself, so the next load on a normal network gets
        // the full image
        #expect(dataCache.store.keys.sorted() == [lowDataURL.absoluteString])
    }

    @Test func lowDataURLIsNotLoadedForOtherFailures() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure
        let request = ImageRequest(url: primaryURL).with { $0.lowDataURL = lowDataURL }

        // WHEN
        let result = await result(of: pipeline.imageTask(with: request))

        // THEN
        #expect((try? result.get()) == nil)
        #expect(dataLoader.requestedURLs == [primaryURL])
    }

    @Test func otherFailuresSkipLowDataURLForTheAlternatives() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = failure
        let request = request(mirrorURL).with { $0.lowDataURL = lowDataURL }

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(dataLoader.requestedURLs == [primaryURL, mirrorURL])
        #expect(response.request.url == mirrorURL)
    }

    @Test func alternativesFollowLowDataURLWhenThatFails() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = constrained
        dataLoader.results[lowDataURL] = failure
        let request = request(mirrorURL).with { $0.lowDataURL = lowDataURL }

        // WHEN
        let task = pipeline.imageTask(with: request)
        let response = try await task.response

        // THEN
        #expect(dataLoader.requestedURLs == [primaryURL, lowDataURL, mirrorURL])
        #expect(response.request.url == mirrorURL)
        #expect(task.metrics?.fallbacks?.count == 2)
    }

    @Test func constrainedFailureWithoutLowDataURLGoesToTheAlternatives() async throws {
        // GIVEN a request the app itself kept off constrained networks
        dataLoader.results[primaryURL] = constrained
        var urlRequest = URLRequest(url: primaryURL)
        urlRequest.allowsConstrainedNetworkAccess = false
        let request = ImageRequest(urlRequest: urlRequest).with { $0.alternatives = [.url(mirrorURL)] }

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.request.url == mirrorURL)
    }

    @Test func cachedSourceIsServedInLowDataMode() async throws {
        // GIVEN the full image on disk
        dataCache.store[primaryURL.absoluteString] = Test.data
        dataLoader.results[primaryURL] = constrained
        let request = ImageRequest(url: primaryURL).with { $0.lowDataURL = lowDataURL }

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN nothing is requested
        #expect(dataLoader.createdTaskCount == 0)
        #expect(response.request.url == primaryURL)
    }

    @Test func requestsOnEitherSideOfTheConstraintDontShareADownload() async throws {
        // GIVEN one request that can use a constrained network and one that can't
        let plain = ImageRequest(url: primaryURL)
        let restricted = plain.with { $0.lowDataURL = lowDataURL }

        // WHEN
        let (first, second) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) { [pipeline] in
            (pipeline.imageTask(with: plain), pipeline.imageTask(with: restricted))
        }
        _ = try await first.response
        _ = try await second.response

        // THEN
        #expect(dataLoader.createdTaskCount == 2)
        #expect(Set(dataLoader.requests.map(\.allowsConstrainedNetworkAccess)) == [true, false])
    }

    @Test func requestsWithDifferentLowDataURLsShareADownload() async throws {
        // GIVEN
        dataLoader.results[primaryURL] = constrained
        let other = URL(string: "http://test.com/other-low-data.jpeg")!
        let first = ImageRequest(url: primaryURL).with { $0.lowDataURL = lowDataURL }
        let second = ImageRequest(url: primaryURL).with { $0.lowDataURL = other }

        // WHEN
        let (firstTask, secondTask) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) { [pipeline] in
            (pipeline.imageTask(with: first), pipeline.imageTask(with: second))
        }
        let firstResponse = try await firstTask.response
        let secondResponse = try await secondTask.response

        // THEN
        #expect(dataLoader.requestedURLs.filter { $0 == primaryURL }.count == 1)
        #expect(firstResponse.request.url == lowDataURL)
        #expect(secondResponse.request.url == other)
    }

    @Test func lowDataURLKeepsTheRestOfTheURLRequest() async throws {
        // GIVEN
        var urlRequest = URLRequest(url: primaryURL, cachePolicy: .reloadIgnoringLocalCacheData)
        urlRequest.setValue("token", forHTTPHeaderField: "X-Token")
        let request = ImageRequest(urlRequest: urlRequest).with { $0.lowDataURL = lowDataURL }

        // WHEN
        _ = try await pipeline.imageTask(with: request).response

        // THEN
        let sent = try #require(dataLoader.requests.first)
        #expect(sent.allowsConstrainedNetworkAccess == false)
        #expect(sent.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(sent.value(forHTTPHeaderField: "X-Token") == "token")
    }

    @Test func lowDataURLOfAFetchClosureIsIgnored() async throws {
        // GIVEN
        let data = Test.data
        let request = ImageRequest(id: "image", data: { data }).with { $0.lowDataURL = lowDataURL }

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(dataLoader.createdTaskCount == 0)
        #expect(response.request.imageID == "image")
    }
}

/// What a constrained network does to a request through `URLSession`, short of
/// a network in Low Data Mode, which a test can't turn on.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineLowDataModeSessionTests {
    @Test func failureFromURLSessionReachesTheLowDataURL() async throws {
        // GIVEN a server standing in for the system, which fails the request
        // that isn't allowed on the network
        let didAllowConstrainedAccess = OSAllocatedUnfairLock<[Bool]>(initialState: [])
        let primaryURL = StubURLProtocol.register { stub in
            didAllowConstrainedAccess.withLock { $0.append(stub.request.allowsConstrainedNetworkAccess) }
            stub.client?.urlProtocol(stub, didFailWithError: URLError(.notConnectedToInternet, userInfo: [
                NSURLErrorNetworkUnavailableReasonKey: URLError.NetworkUnavailableReason.constrained.rawValue
            ]))
        }
        let lowDataURL = StubURLProtocol.register { stub in
            didAllowConstrainedAccess.withLock { $0.append(stub.request.allowsConstrainedNetworkAccess) }
            stub.respond(chunks: [Test.data])
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let pipeline = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: configuration)
            $0.imageCache = nil
        }

        // WHEN
        var request = ImageRequest(url: primaryURL)
        request.lowDataURL = lowDataURL
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.request.url == lowDataURL)
        #expect(didAllowConstrainedAccess.withLock { $0 } == [false, true])
    }
}

/// The two properties as parts of a request, which don't otherwise change it.
@Suite struct ImageRequestFallbackTests {
    private let mirrorURL = URL(string: "http://test.com/mirror.jpeg")!
    private let lowDataURL = URL(string: "http://test.com/low-data.jpeg")!

    @Test func defaults() {
        let request = ImageRequest(url: Test.url)

        #expect(request.alternatives.isEmpty)
        #expect(request.lowDataURL == nil)
        #expect(!request.hasFallbacks)
    }

    @Test func requestKeepsWhatItIsAndGainsTheFallbacks() {
        // GIVEN
        let processor = MockImageProcessor(id: "1")
        var request = ImageRequest(url: Test.url, processors: [processor], priority: .high, options: [.disableMemoryCache])
        request.imageID = "id"

        // WHEN
        request.alternatives = [.url(mirrorURL)]
        request.lowDataURL = lowDataURL

        // THEN
        #expect(request.url == Test.url)
        #expect(request.imageID == "id")
        #expect(request.processors.count == 1)
        #expect(request.priority == .high)
        #expect(request.options == [.disableMemoryCache])
        #expect(request.alternatives.count == 1)
        #expect(request.lowDataURL == lowDataURL)
        #expect(request.description.contains(Test.url.absoluteString))
    }

    @Test func copiesAreIndependent() {
        // GIVEN
        let request = ImageRequest(url: Test.url)
        var copy = request

        // WHEN
        copy.alternatives = [.url(mirrorURL)]

        // THEN
        #expect(request.alternatives.isEmpty)
        #expect(copy.alternatives.count == 1)
    }

    @Test func removingTheFallbacksRestoresTheRequest() {
        // GIVEN
        var request = ImageRequest(url: Test.url)
        request.alternatives = [.url(mirrorURL)]
        request.lowDataURL = lowDataURL

        // WHEN
        request.alternatives = []
        #expect(request.hasFallbacks)
        request.lowDataURL = nil

        // THEN
        #expect(!request.hasFallbacks)
        #expect(request.urlRequest?.allowsConstrainedNetworkAccess == true)
        if case .url = request.resourceWithFallbacks {} else {
            Issue.record("Expected a plain resource")
        }
    }

    @Test func settingThePropertyTwiceDoesntNestTheResource() {
        // GIVEN
        var request = ImageRequest(url: Test.url)

        // WHEN
        request.alternatives = [.url(mirrorURL)]
        request.alternatives = [.url(lowDataURL)]

        // THEN
        if case .url = request.resource {} else {
            Issue.record("Expected the primary resource to be plain")
        }
        #expect(request.alternatives.map(\.id) == [lowDataURL.absoluteString])
    }

    @Test func urlRequestIsLazyWithoutLowDataURL() {
        // GIVEN
        let request = ImageRequest(url: Test.url)

        // THEN the fast path of the key has nothing to build
        if case .url = request.resourceWithFallbacks {} else {
            Issue.record("Expected a plain resource")
        }
    }

    @Test func keyTellsTheConstrainedRequestApart() {
        // GIVEN
        let plain = ImageRequest(url: Test.url)
        let withLowDataURL = plain.with { $0.lowDataURL = lowDataURL }
        var urlRequest = URLRequest(url: Test.url)
        urlRequest.allowsConstrainedNetworkAccess = false
        let restricted = ImageRequest(urlRequest: urlRequest)

        // THEN
        #expect(TaskFetchOriginalDataKey(plain) != TaskFetchOriginalDataKey(withLowDataURL))
        #expect(TaskFetchOriginalDataKey(plain) != TaskFetchOriginalDataKey(restricted))
        #expect(TaskFetchOriginalDataKey(withLowDataURL) == TaskFetchOriginalDataKey(restricted))
        // AND the data cache doesn't care: the image is the same
        #expect(MemoryCacheKey(plain) == MemoryCacheKey(withLowDataURL))
    }

    @Test func keyOfAURLRequestWithFallbacksIsTheKeyOfTheURLRequest() {
        // GIVEN
        let urlRequest = URLRequest(url: Test.url, cachePolicy: .returnCacheDataDontLoad)
        let plain = ImageRequest(urlRequest: urlRequest)
        let other = plain.with { $0.alternatives = [.url(mirrorURL)] }

        // THEN
        #expect(TaskFetchOriginalDataKey(plain) == TaskFetchOriginalDataKey(other))
    }

    @Test func requestForASourceKeepsEverythingButTheSource() {
        // GIVEN
        let processor = MockImageProcessor(id: "1")
        var request = ImageRequest(url: Test.url, processors: [processor], priority: .high, options: [.disableMemoryCache])
        request.imageID = "custom"
        request.scale = 2
        request.thumbnail = .init(maxPixelSize: 100)
        request.userInfo["key"] = "value"
        request.label = "feed"
        request.alternatives = [.url(mirrorURL)]

        // WHEN
        let copy = request.withSource(.url(mirrorURL))

        // THEN
        #expect(copy.url == mirrorURL)
        #expect(copy.imageID == mirrorURL.absoluteString)
        #expect(copy.alternatives.isEmpty)
        #expect(copy.processorsIdentity == request.processorsIdentity)
        #expect(copy.processors.count == 1)
        #expect(copy.priority == .high)
        #expect(copy.options == [.disableMemoryCache])
        #expect(copy.scale == 2)
        #expect(copy.thumbnail == request.thumbnail)
        #expect(copy.userInfo["key"] as? String == "value")
        #expect(copy.label == "feed")
    }

    @Test func sourcesAreIdentified() {
        let urlRequest = URLRequest(url: mirrorURL)

        #expect(ImageSource.url(mirrorURL).id == mirrorURL.absoluteString)
        #expect(ImageSource.urlRequest(urlRequest).id == mirrorURL.absoluteString)
        #expect(ImageSource.data(id: "a") { Data() }.id == "a")
        #expect(ImageSource.image(id: "b") { Test.container }.id == "b")
    }

    @Test func fallbacksAreCompared() {
        let plain = ImageRequest(url: Test.url)
        let other = plain.with { $0.alternatives = [.url(mirrorURL)] }

        #expect(plain.hasSameFallbacks(as: ImageRequest(url: Test.url)))
        #expect(!plain.hasSameFallbacks(as: other))
        #expect(!other.hasSameFallbacks(as: plain))
        #expect(other.hasSameFallbacks(as: plain.with { $0.alternatives = [.url(mirrorURL)] }))
        #expect(!other.hasSameFallbacks(as: other.with { $0.lowDataURL = lowDataURL }))
    }
}
