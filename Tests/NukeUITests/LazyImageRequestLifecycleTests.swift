// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import SwiftUI
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

/// Covers what happens to a `LazyImage` request over the life of the view:
/// the request changing under it, the view leaving and coming back, and what
/// the content sees at each step.
@Suite(.serialized, .timeLimit(.minutes(5))) @MainActor
struct LazyImageRequestLifecycleTests {
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline

    private let otherURL = URL(string: "https://example.com/other.jpeg")!

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
            $0.dataCache = MockDataCache()
        }
    }

    // MARK: - Default Content

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
    @Test func defaultContentPlaysAnimatedImagesAndDropsThePlayerForAStill() async throws {
        serveGIF(at: Test.url, frameCount: 3)

        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let first = TestExpectation()
        let second = TestExpectation()
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onCompletion {
                    results.value.append($0)
                    if results.value.count == 1 { first.fulfill() } else { second.fulfill() }
                }
        }
        await first.wait()
        await host.render(until: { host.firstView(ofType: AnimatedImageView.self) != nil })

        // The default content plays the animation instead of showing the still,
        // and is never blank: the still is on screen until the first frame is.
        let animatedView = try #require(host.firstView(ofType: AnimatedImageView.self))
        #expect(animatedView.animatedImage?.frameCount == 3)
        #expect(animatedView.image != nil)

        // A still image that replaces it leaves no player behind.
        await host.update(otherURL)
        await second.wait()
        await host.render(until: { host.firstView(ofType: AnimatedImageView.self) == nil })

        #expect(host.firstView(ofType: AnimatedImageView.self) == nil)
        #expect(try #require(results.value.last).value?.request.url == otherURL)
    }
#endif

    // MARK: - Content State

    /// Reading the progress in the content is what opts the view into the
    /// progress updates: a chunk of data changes nothing else, so without them
    /// the content would never see the download move.
    @Test func contentIsUpdatedWithTheDownloadProgress() async throws {
        let progressiveLoader = MockProgressiveDataLoader()
        progressiveLoader.servesFirstChunkAutomatically = false
        let progressivePipeline = ImagePipeline {
            $0.dataLoader = progressiveLoader
            $0.imageCache = nil
        }
        let total = Int64(progressiveLoader.data.count)
        let firstChunk = Int64(try #require(progressiveLoader.chunks.first).count)

        let states = Ref<[(isLoading: Bool, progress: ImageTask.Progress)]>([])
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url) { state in
                let _ = states.value.append((state.isLoading, state.progress))
                SwiftUI.Color.clear
            }
            .pipeline(progressivePipeline)
        }
        await host.render(until: { states.value.last?.isLoading == true })
        #expect(states.value.first?.progress == ImageTask.Progress(completed: 0, total: 0))

        progressiveLoader.resume() // Serves the first chunk and holds the rest
        // Nothing to wait on but the content itself, and the chunk makes a
        // round trip through the pipeline: more time than one `render` gives.
        let sawFirstChunk = { states.value.last?.progress.completed == firstChunk }
        for _ in 0..<25 where !sawFirstChunk() {
            await host.render(until: sawFirstChunk)
        }

        let last = try #require(states.value.last)
        #expect(last.isLoading)
        #expect(last.progress == ImageTask.Progress(completed: firstChunk, total: total))
    }

    @Test func settingTheURLToNilClearsTheDisplayedImage() async throws {
        let states = Ref<[(hasImage: Bool, error: ImagePipeline.Error?)]>([])
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let first = TestExpectation()
        let second = TestExpectation()
        let host = ViewHost(Optional(Test.url)) { url in
            LazyImage(url: url) { state in
                let _ = states.value.append((state.image != nil, state.error))
                SwiftUI.Color.clear
            }
            .pipeline(pipeline)
            .onCompletion {
                results.value.append($0)
                if results.value.count == 1 { first.fulfill() } else { second.fulfill() }
            }
        }
        await first.wait()
        await host.render(until: { states.value.last?.hasImage == true })

        await host.update(nil)
        await second.wait()
        await host.render(until: { states.value.last?.hasImage == false })

        #expect(try #require(results.value.last).error == .imageRequestMissing)
        let last = try #require(states.value.last)
        #expect(!last.hasImage)
        #expect(last.error == .imageRequestMissing)
    }

    @Test func settingTheURLAfterStartingWithNilLoadsTheImage() async throws {
        let states = Ref<[(hasImage: Bool, error: ImagePipeline.Error?)]>([])
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let first = TestExpectation()
        let second = TestExpectation()
        let host = ViewHost(nil as URL?) { url in
            LazyImage(url: url) { state in
                let _ = states.value.append((state.image != nil, state.error))
                SwiftUI.Color.clear
            }
            .pipeline(pipeline)
            .onCompletion {
                results.value.append($0)
                if results.value.count == 1 { first.fulfill() } else { second.fulfill() }
            }
        }
        await first.wait()
        #expect(try #require(results.value.first).error == .imageRequestMissing)

        await host.update(Test.url)
        await second.wait()
        await host.render(until: { states.value.last?.hasImage == true })

        #expect(try #require(results.value.last).isSuccess)
        // The error of the missing request doesn't outlive it.
        let last = try #require(states.value.last)
        #expect(last.hasImage)
        #expect(last.error == nil)
    }

    /// A memory cache hit is looked up synchronously when the view appears, so
    /// the content never renders a loading state for it.
    @Test func memoryCacheHitIsRenderedWithoutALoadingState() async throws {
        pipeline.cache[Test.request] = Test.container

        let states = Ref<[(isLoading: Bool, hasImage: Bool)]>([])
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url) { state in
                let _ = states.value.append((state.isLoading, state.image != nil))
                SwiftUI.Color.clear
            }
            .pipeline(pipeline)
        }
        await host.render(until: { states.value.last?.hasImage == true })

        #expect(try #require(states.value.last).hasImage)
        #expect(!states.value.contains { $0.isLoading })
    }

    // MARK: - Request Changes

    @Test func changingTheURLWhileLoadingCancelsThePreviousRequest() async throws {
        dataLoader.isSuspended = true

        let tasks = Ref<[ImageTask]>([])
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let started = TestExpectation()
        let completed = TestExpectation()
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onStart {
                    tasks.value.append($0)
                    started.fulfill()
                }
                .onCompletion {
                    results.value.append($0)
                    completed.fulfill()
                }
        }
        await started.wait()

        await host.update(otherURL, until: { tasks.value.count == 2 })
        let first = try #require(tasks.value.first)
        #expect(first.isCancelled)
        #expect(tasks.value.count == 2)

        dataLoader.isSuspended = false
        await completed.wait()
        await host.render()

        // Only the current request reports back: the result of the replaced
        // one must never land on the new request.
        #expect(results.value.count == 1)
        #expect(try #require(results.value.first).value?.request.url == otherURL)
    }

    @Test func changingToAMemoryCachedRequestWhileLoadingDisplaysItImmediately() async throws {
        dataLoader.isSuspended = true
        pipeline.cache[ImageRequest(url: otherURL)] = Test.container

        let tasks = Ref<[ImageTask]>([])
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let started = TestExpectation()
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onStart {
                    tasks.value.append($0)
                    started.fulfill()
                }
                .onCompletion { results.value.append($0) }
        }
        await started.wait()

        // The cached image is delivered synchronously, with no task started.
        await host.update(otherURL, until: { !results.value.isEmpty })

        let first = try #require(tasks.value.first)
        #expect(first.isCancelled)
        #expect(tasks.value.count == 1)
        let result = try #require(results.value.first)
        #expect(result.value?.cacheType == .memory)
        #expect(result.value?.request.url == otherURL)

        dataLoader.isSuspended = false
        await host.render()

        #expect(results.value.count == 1)
    }

    /// The fast path compares requests by identity, and a view that rebuilds
    /// its processors on every update never hits it: the processors have to
    /// compare equal by their identifiers.
    @Test func recreatingEqualProcessorsOnUpdateDoesNotReload() async {
        let completions = Ref(0)
        let first = TestExpectation()
        let host = ViewHost(0) { _ in
            LazyImage(url: Test.url)
                .pipeline(pipeline)
                .processors([MockImageProcessor(id: "p1"), MockImageProcessor(id: "p2")])
                .onCompletion { _ in
                    completions.value += 1
                    first.fulfill()
                }
        }
        await first.wait()

        await host.update(1)
        await host.render()

        // A reload would complete again, from the memory cache.
        #expect(completions.value == 1)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func changingTheRequestOptionsReloads() async throws {
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let first = TestExpectation()
        let second = TestExpectation()
        let host = ViewHost(ImageRequest.Options()) { options in
            LazyImage(request: ImageRequest(url: Test.url, options: options))
                .pipeline(pipeline)
                .onCompletion {
                    results.value.append($0)
                    if results.value.count == 1 { first.fulfill() } else { second.fulfill() }
                }
        }
        await first.wait()

        await host.update(.reloadIgnoringCachedData)
        await second.wait()

        // The new options bypass the memory cache the first load populated.
        #expect(try #require(results.value.last).value?.cacheType == nil)
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func changingTheImageIDReloads() async throws {
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let first = TestExpectation()
        let second = TestExpectation()
        let host = ViewHost("image-a") { imageID in
            LazyImage(request: makeRequest(imageID: imageID))
                .pipeline(pipeline)
                .onCompletion {
                    results.value.append($0)
                    if results.value.count == 1 { first.fulfill() } else { second.fulfill() }
                }
        }
        await first.wait()

        await host.update("image-b")
        await second.wait()

        #expect(results.value.count == 2)
        #expect(try #require(results.value.last).value?.request.imageID == "image-b")
    }

    /// A failed request isn't retried by re-rendering with the same request;
    /// giving the view a new identity is the way to retry it.
    @Test func newIdentityRetriesAFailedRequest() async throws {
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))

        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let first = TestExpectation()
        let second = TestExpectation()
        let host = ViewHost(0) { attempt in
            LazyImage(url: Test.url)
                .pipeline(pipeline)
                .onCompletion {
                    results.value.append($0)
                    if results.value.count == 1 { first.fulfill() } else { second.fulfill() }
                }
                .id(attempt)
        }
        await first.wait()
        #expect(try #require(results.value.first).isFailure)

        dataLoader.results[Test.url] = nil // Serves the default image
        await host.update(1)
        await second.wait()

        #expect(results.value.count == 2)
        #expect(try #require(results.value.last).isSuccess)
        #expect(dataLoader.createdTaskCount == 2)
    }

    // MARK: - Disappear and Reappear

    /// The view comes back with the image it had, straight from the memory
    /// cache, without flashing the placeholder or downloading it again.
    @Test func loadedImageSurvivesDisappearingAndReappearing() async throws {
        let hasImage = Ref<[Bool]>([])
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let first = TestExpectation()
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url) { state in
                let _ = hasImage.value.append(state.image != nil)
                SwiftUI.Color.clear
            }
            .pipeline(pipeline)
            .onCompletion {
                results.value.append($0)
                first.fulfill()
            }
        }
        await first.wait()
        await host.render(until: { hasImage.value.last == true })

        await host.hideContent()
        let evaluationsBeforeReappearing = hasImage.value.count
        await host.showContent(until: { results.value.count == 2 })
        await host.render()

        #expect(results.value.count == 2)
        #expect(try #require(results.value.last).value?.cacheType == .memory)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(!hasImage.value[evaluationsBeforeReappearing...].contains(false))
    }

    @Test func requestCancelledOnDisappearIsRestartedAndCompletesOnReappear() async throws {
        dataLoader.isSuspended = true

        let tasks = Ref<[ImageTask]>([])
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let started = TestExpectation()
        let completed = TestExpectation()
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onStart {
                    tasks.value.append($0)
                    started.fulfill()
                }
                .onCompletion {
                    results.value.append($0)
                    completed.fulfill()
                }
        }
        await started.wait()
        let firstTask = try #require(tasks.value.first)

        await host.hideContent(until: { firstTask.isCancelled })
        await host.showContent(until: { tasks.value.count == 2 })

        let secondTask = try #require(tasks.value.last)
        #expect(secondTask !== firstTask)
        #expect(!secondTask.isCancelled)

        dataLoader.isSuspended = false
        await completed.wait()

        // The cancelled request reports nothing, the restarted one succeeds.
        #expect(results.value.count == 1)
        #expect(try #require(results.value.first).isSuccess)
    }

    /// The point of lowering the priority instead of cancelling: the request
    /// keeps going off screen, and the view comes back to a finished image.
    @Test func requestWithLoweredPriorityFinishesOffScreen() async throws {
        dataLoader.isSuspended = true

        let tasks = Ref<[ImageTask]>([])
        let results = Ref<[Result<ImageResponse, ImagePipeline.Error>]>([])
        let started = TestExpectation()
        let completed = TestExpectation()
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onDisappear(.lowerPriority)
                .onStart {
                    tasks.value.append($0)
                    started.fulfill()
                }
                .onCompletion {
                    results.value.append($0)
                    completed.fulfill()
                }
        }
        await started.wait()
        let task = try #require(tasks.value.first)

        await host.hideContent(until: { task.priority == .veryLow })
        dataLoader.isSuspended = false
        await completed.wait()

        #expect(try #require(results.value.first).isSuccess)

        await host.showContent(until: { results.value.count == 2 })

        #expect(results.value.count == 2)
        #expect(try #require(results.value.last).value?.cacheType == .memory)
        #expect(tasks.value.count == 1)
        #expect(dataLoader.createdTaskCount == 1)
    }

    /// The priority lowered on disappear goes back to the one the view asks
    /// for, not to the default one.
    @Test func reappearingRestoresThePriorityFromTheModifier() async throws {
        dataLoader.isSuspended = true

        let tasks = Ref<[ImageTask]>([])
        let started = TestExpectation()
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .priority(.high)
                .onDisappear(.lowerPriority)
                .onStart {
                    tasks.value.append($0)
                    started.fulfill()
                }
        }
        await started.wait()
        let task = try #require(tasks.value.first)
        #expect(task.priority == .high)

        await host.hideContent(until: { task.priority == .veryLow })
        #expect(task.priority == .veryLow)

        await host.showContent(until: { tasks.value.last?.priority == .high })

        let current = try #require(tasks.value.last)
        #expect(current.priority == .high)
        #expect(!current.isCancelled)
    }

    // MARK: - Helpers

    private func serveGIF(at url: URL, frameCount: Int) {
        let data = Test.animatedGIF(frameCount: frameCount)
        dataLoader.results[url] = .success((data, URLResponse(
            url: url,
            mimeType: "image/gif",
            expectedContentLength: data.count,
            textEncodingName: nil
        )))
    }

    private func makeRequest(imageID: String) -> ImageRequest {
        var request = ImageRequest(url: Test.url)
        request.imageID = imageID
        return request
    }
}

#endif
