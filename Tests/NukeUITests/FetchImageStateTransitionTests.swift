// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Combine
import SwiftUI
@testable import Nuke
@testable import NukeUI

/// Covers the order and consistency of the `FetchImage` state as one load
/// replaces another, and what the callbacks see when they run.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct FetchImageStateTransitionTests {
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline
    let image: FetchImage

    private let otherURL = URL(string: "https://example.com/other.jpeg")!

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
            $0.dataCache = MockDataCache()
        }
        self.image = FetchImage()
        self.image.pipeline = pipeline
    }

    // MARK: - Replacing the Displayed Image

    @Test func loadingNilClearsThePreviouslyLoadedImage() async throws {
        _ = try await image.loadAndWait(Test.request)?.get()
        #expect(image.imageContainer != nil)

        image.load(nil as URL?)

        #expect(image.imageContainer == nil)
        #expect(image.image == nil)
        #expect(!image.isLoading)
        #expect(try #require(image.result).error == .imageRequestMissing)
    }

    @Test func failedLoadDoesNotKeepTheImageOfThePreviousLoad() async throws {
        _ = try await image.loadAndWait(Test.request)?.get()
        dataLoader.results[otherURL] = .failure(NSError(domain: "test", code: 42))

        let completed = TestExpectation()
        image.onCompletion = { _ in completed.fulfill() }
        image.load(otherURL)
        #expect(image.imageContainer == nil) // Cleared as soon as the new load starts
        await completed.wait()

        #expect(image.imageContainer == nil)
        let error = try #require(image.result?.error)
        #expect((error.dataLoadingError as? NSError)?.code == 42)
    }

    /// A memory cache hit sets the new image directly, so a view never
    /// blinks the placeholder between two images.
    @Test func memoryCacheHitReplacesTheImageWithoutPublishingNil() async throws {
        _ = try await image.loadAndWait(Test.request)?.get()
        let cached = ImageContainer(image: Test.image)
        pipeline.cache[ImageRequest(url: otherURL)] = cached

        var published: [ImageContainer?] = []
        let cancellable = image.$imageContainer.dropFirst().sink { published.append($0) }
        image.load(otherURL)
        cancellable.cancel()

        #expect(published.count == 1)
        #expect(!published.contains { $0 == nil })
        #expect(image.imageContainer?.image === cached.image)
        #expect(try #require(image.result).value?.cacheType == .memory)
    }

    /// The overrides are applied before the lookup: a lookup with the request
    /// as passed would miss the image the pipeline stored for the processed one.
    @Test func memoryCacheLookupUsesTheProcessorAndPriorityOverrides() throws {
        image.processors = [MockImageProcessor(id: "p1")]
        image.priority = .high
        pipeline.cache[ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])] = Test.container

        let starts = Ref(0)
        image.onStart = { _ in starts.value += 1 }
        image.load(Test.request)

        let response = try #require(image.result?.value)
        #expect(response.cacheType == .memory)
        #expect(response.request.processors.map(\.identifier) == ["p1"])
        #expect(response.request.priority == .high)
        #expect(starts.value == 0) // No task to start
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func memoryCacheIsSkippedWhenTheRequestDisablesMemoryCacheReads() async throws {
        pipeline.cache[Test.request] = Test.container

        let request = ImageRequest(url: Test.url, options: [.disableMemoryCacheReads])
        let completed = TestExpectation()
        image.onCompletion = { _ in completed.fulfill() }
        image.load(request)
        #expect(image.isLoading)
        #expect(image.result == nil)
        await completed.wait()

        #expect(try #require(image.result).value?.cacheType == nil)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func invalidatedPipelineFailsTheLoad() async throws {
        pipeline.invalidate()

        let completed = TestExpectation()
        image.onCompletion = { _ in completed.fulfill() }
        image.load(Test.request)
        await completed.wait()

        #expect(try #require(image.result).error == .pipelineInvalidated)
        #expect(image.imageContainer == nil)
        #expect(!image.isLoading)
        #expect(dataLoader.createdTaskCount == 0)
    }

    // MARK: - State Seen by the Callbacks

    /// A snapshot of the state taken inside `onCompletion`.
    private struct CompletionSnapshot {
        var isLoading: Bool
        var hasResult: Bool
        var hasImage: Bool
        var isSuccess: Bool
    }

    /// Runs `load` and returns the state as `onCompletion` saw it.
    private func snapshotAtCompletion(_ load: (FetchImage) -> Void) async throws -> CompletionSnapshot {
        let image = FetchImage()
        image.pipeline = pipeline
        let completed = TestExpectation()
        let snapshot = Ref<CompletionSnapshot?>(nil)
        image.onCompletion = { [unowned image] result in
            snapshot.value = CompletionSnapshot(
                isLoading: image.isLoading,
                hasResult: image.result != nil,
                hasImage: image.imageContainer != nil,
                isSuccess: result.isSuccess
            )
            completed.fulfill()
        }
        load(image)
        await completed.wait()
        return try #require(snapshot.value)
    }

    @Test func stateIsFinalWhenOnCompletionIsCalledForADownload() async throws {
        let snapshot = try await snapshotAtCompletion { $0.load(Test.request) }
        #expect(snapshot.isSuccess)
        #expect(!snapshot.isLoading)
        #expect(snapshot.hasResult)
        #expect(snapshot.hasImage)
    }

    @Test func stateIsFinalWhenOnCompletionIsCalledForAFailedDownload() async throws {
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 1))
        let snapshot = try await snapshotAtCompletion { $0.load(Test.request) }
        #expect(!snapshot.isSuccess)
        #expect(!snapshot.isLoading)
        #expect(snapshot.hasResult)
        #expect(!snapshot.hasImage)
    }

    @Test func stateIsFinalWhenOnCompletionIsCalledForAMemoryCacheHit() async throws {
        pipeline.cache[Test.request] = Test.container
        let snapshot = try await snapshotAtCompletion { $0.load(Test.request) }
        #expect(snapshot.isSuccess)
        #expect(!snapshot.isLoading)
        #expect(snapshot.hasResult)
        #expect(snapshot.hasImage)
    }

    @Test func stateIsFinalWhenOnCompletionIsCalledForAMissingRequest() async throws {
        let snapshot = try await snapshotAtCompletion { $0.load(nil as ImageRequest?) }
        #expect(!snapshot.isSuccess)
        #expect(!snapshot.isLoading)
        #expect(snapshot.hasResult)
        #expect(!snapshot.hasImage)
    }

    @Test func stateIsFinalWhenOnCompletionIsCalledForAnAsyncLoad() async throws {
        let snapshot = try await snapshotAtCompletion { $0.load { Test.response } }
        #expect(snapshot.isSuccess)
        #expect(!snapshot.isLoading)
        #expect(snapshot.hasResult)
        #expect(snapshot.hasImage)
    }

    @Test func stateIsFinalWhenOnCompletionIsCalledForAFailedAsyncLoad() async throws {
        struct LoadError: Error {}
        let snapshot = try await snapshotAtCompletion { $0.load { throw LoadError() } }
        #expect(!snapshot.isSuccess)
        #expect(!snapshot.isLoading)
        #expect(snapshot.hasResult)
        #expect(!snapshot.hasImage)
    }

    // MARK: - Superseding Loads

    @Test func newLoadCancelsTheRequestInFlight() async throws {
        dataLoader.isSuspended = true

        let tasks = Ref<[ImageTask]>([])
        image.onStart = { tasks.value.append($0) }
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let completed = TestExpectation()
        image.onCompletion = {
            results.value.append($0)
            completed.fulfill()
        }

        image.load(Test.request)
        image.load(otherURL)

        #expect(tasks.value.count == 2)
        #expect(tasks.value[0].isCancelled)
        #expect(!tasks.value[1].isCancelled)
        #expect(image.isLoading)

        dataLoader.isSuspended = false
        await completed.wait()

        #expect(results.value.count == 1)
        #expect(try #require(results.value.first).value?.request.url == otherURL)
        #expect(image.result?.value?.request.url == otherURL)
    }

#if !os(watchOS)
    /// The completion of the replaced request has already been dispatched to
    /// the main queue when the next load starts. It must still be dropped, or
    /// it would overwrite the image the new load found in the memory cache –
    /// the classic cell reuse bug.
    @Test func lateResponseOfReplacedRequestIsDropped() async throws {
        let observer = ImagePipelineObserver()
        let pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
        }
        image.pipeline = pipeline
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        image.onCompletion = { results.value.append($0) }

        // Given the first request finishes in the pipeline while the main
        // thread is busy, so its completion can't run yet
        try runWhileMainThreadIsBlocked(untilTaskCompletes: observer) {
            image.load(Test.request)
        }

        // When the next request is a memory cache hit, loaded before the main
        // queue drains
        let cached = ImageContainer(image: Test.image)
        pipeline.cache[ImageRequest(url: otherURL)] = cached
        image.load(otherURL)
        await waitForDelivery()

        // Then only the new request is reported and displayed
        #expect(results.value.count == 1)
        #expect(try #require(results.value.first).value?.request.url == otherURL)
        #expect(image.result?.value?.request.url == otherURL)
        #expect(image.imageContainer?.image === cached.image)
    }
#endif

    @Test func asyncLoadCancelsThePipelineRequestInFlight() async throws {
        dataLoader.isSuspended = true

        let tasks = Ref<[ImageTask]>([])
        image.onStart = { tasks.value.append($0) }
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let completed = TestExpectation()
        image.onCompletion = {
            results.value.append($0)
            completed.fulfill()
        }

        image.load(Test.request)
        let asyncResponse = ImageResponse(container: Test.container, request: ImageRequest(url: otherURL))
        image.load { asyncResponse }

        #expect(try #require(tasks.value.first).isCancelled)
        await completed.wait()
        dataLoader.isSuspended = false
        await drainPendingWork()

        #expect(tasks.value.count == 1) // The async load has no task to report
        #expect(results.value.count == 1)
        #expect(image.result?.value?.request.url == otherURL)
    }

    @Test func pipelineLoadSupersedesTheAsyncLoadInFlight() async throws {
        let gate = AsyncGate()
        let actionStarted = TestExpectation()
        let actionReturned = TestExpectation()
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let completed = TestExpectation()
        image.onCompletion = {
            results.value.append($0)
            completed.fulfill()
        }

        // The action ignores cancellation, so it returns after being superseded.
        let staleResponse = ImageResponse(container: Test.container, request: ImageRequest(url: otherURL))
        image.load {
            actionStarted.fulfill()
            await gate.wait()
            actionReturned.fulfill()
            return staleResponse
        }
        await actionStarted.wait()

        image.load(Test.request)
        await completed.wait()

        gate.open()
        await actionReturned.wait()
        await drainPendingWork()

        #expect(results.value.count == 1)
        #expect(image.result?.value?.request.url == Test.url)
        #expect(!image.isLoading)
    }

    @Test func missingRequestSupersedesTheAsyncLoadInFlight() async throws {
        let gate = AsyncGate()
        let actionStarted = TestExpectation()
        let actionReturned = TestExpectation()
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        image.onCompletion = { results.value.append($0) }

        image.load {
            actionStarted.fulfill()
            await gate.wait()
            actionReturned.fulfill()
            return Test.response
        }
        await actionStarted.wait()

        image.load(nil as URL?)
        #expect(results.value.count == 1)

        gate.open()
        await actionReturned.wait()
        await drainPendingWork()

        #expect(results.value.count == 1)
        #expect(try #require(image.result).error == .imageRequestMissing)
        #expect(image.imageContainer == nil)
        #expect(!image.isLoading)
    }

    // MARK: - Re-entrancy

    /// A fallback started from the completion of a failed load, the way an
    /// app shows a default avatar.
    @Test func loadStartedFromOnCompletionRuns() async throws {
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 1))

        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let fallbackStarted = TestExpectation()
        let completed = TestExpectation()
        let fallbackURL = otherURL
        let image = self.image
        let dataLoader = self.dataLoader
        image.onCompletion = { [unowned image] result in
            results.value.append(result)
            if result.isFailure {
                dataLoader.isSuspended = true // Holds the fallback in flight
                image.load(fallbackURL)
                fallbackStarted.fulfill()
            } else {
                completed.fulfill()
            }
        }
        image.load(Test.request)
        await fallbackStarted.wait()

        // The failed load is done handling its result by the time the test
        // resumes, and none of its state may land on the fallback.
        #expect(image.isLoading)
        #expect(image.result == nil)

        dataLoader.isSuspended = false
        await completed.wait()

        #expect(results.value.count == 2)
        #expect(try #require(results.value.first).isFailure)
        #expect(image.result?.value?.request.url == fallbackURL)
        #expect(image.imageContainer != nil)
        #expect(!image.isLoading)
    }

    @Test func resetCalledFromOnCompletionWins() async {
        let completed = TestExpectation()
        let image = self.image
        image.onCompletion = { [unowned image] _ in
            image.reset()
            completed.fulfill()
        }
        image.load(Test.request)
        await completed.wait()

        #expect(image.result == nil)
        #expect(image.imageContainer == nil)
        #expect(!image.isLoading)
    }

    // MARK: - Progress

    @Test func progressIsClearedWhenTheNextLoadStarts() async throws {
        _ = try await image.loadAndWait(Test.request)?.get()
        #expect(image.progress.completed > 0)

        dataLoader.isSuspended = true
        image.load(otherURL)

        #expect(image.isLoading)
        #expect(image.progress == ImageTask.Progress(completed: 0, total: 0))
    }

    @Test func progressIsClearedByAMemoryCacheHit() async throws {
        _ = try await image.loadAndWait(Test.request)?.get()
        #expect(image.progress.completed > 0)
        pipeline.cache[ImageRequest(url: otherURL)] = Test.container

        image.load(otherURL)

        #expect(!image.isLoading)
        #expect(image.progress == ImageTask.Progress(completed: 0, total: 0))
    }

    // MARK: - Cancel and Reset

    /// Documented: cancelling continues to display a downloaded image.
    @Test func cancelKeepsTheLoadedImageAndResult() async throws {
        _ = try await image.loadAndWait(Test.request)?.get()
        let container = try #require(image.imageContainer)

        image.cancel()

        #expect(image.imageContainer?.image === container.image)
        #expect(try #require(image.result).isSuccess)
    }

    @Test func cancelKeepsTheCachedPreviewOnScreen() {
        dataLoader.isSuspended = true
        pipeline.cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        image.load(Test.request)
        #expect(image.imageContainer?.isPreview == true)

        image.cancel()

        #expect(image.imageContainer?.isPreview == true)
        #expect(image.result == nil)
    }

    /// `reset` only publishes the values that change, so resetting an object
    /// that is already empty doesn't invalidate the views that observe it.
    @Test func resetPublishesNothingWhenThereIsNothingToClear() async throws {
        var changes = 0
        let cancellable = image.objectWillChange.sink { _ in changes += 1 }

        image.reset()
        #expect(changes == 0)

        _ = try await image.loadAndWait(Test.request)?.get()
        image.reset()
        let changesAfterFirstReset = changes
        #expect(changesAfterFirstReset > 0)

        image.reset()
        #expect(changes == changesAfterFirstReset)
        withExtendedLifetime(cancellable) {}
    }

    // MARK: - Custom Views

#if !os(watchOS)
    /// The custom view from the `FetchImage` documentation: loads on appear,
    /// reloads when the URL changes, and resets on disappear.
    @Test func documentedCustomViewLoadsReloadsAndResets() async throws {
        let observed = Ref<FetchImage?>(nil)
        let completions = Ref(0)
        let first = TestExpectation()
        let second = TestExpectation()
        let pipeline = self.pipeline
        let host = ViewHost(Test.url) { url in
            DocumentedImageView(url: url, pipeline: pipeline, observed: observed) { _ in
                completions.value += 1
                if completions.value == 1 { first.fulfill() } else { second.fulfill() }
            }
        }
        await first.wait()
        let image = try #require(observed.value)
        #expect(image.result?.value?.request.url == Test.url)

        await host.update(otherURL)
        await second.wait()
        #expect(image.result?.value?.request.url == otherURL)
        #expect(image.imageContainer != nil)

        await host.hideContent(until: { image.result == nil })
        #expect(image.result == nil)
        #expect(image.imageContainer == nil)
        #expect(!image.isLoading)
    }
#endif
}

#if !os(watchOS)
/// The view from Documentation/NukeUI.docc/Extensions/FetchImage-Extensions.md,
/// plus a way for the test to reach the object it owns.
private struct DocumentedImageView: View {
    let url: URL
    let pipeline: ImagePipeline
    let observed: Ref<FetchImage?>
    let onCompletion: @MainActor @Sendable (Result<ImageResponse, ImagePipeline.Error>) -> Void

    @StateObject private var image = FetchImage()

    var body: some View {
        ZStack {
            Rectangle().fill(SwiftUI.Color.gray)
            image.image?
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        }
        .onAppear {
            observed.value = image
            image.pipeline = pipeline
            image.onCompletion = onCompletion
            image.load(url)
        }
        .onChange(of: url) { image.load($1) }
        .onDisappear { image.reset() }
    }
}
#endif
