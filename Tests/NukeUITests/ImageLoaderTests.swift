// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

/// Covers the states an ``ImageLoader`` reports, in what order, and how a load
/// is awaited, cancelled, and replaced.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct ImageLoaderTests {
    let dataLoader: MockDataLoader
    let imageCache: MockImageCache
    let pipeline: ImagePipeline
    let loader: ImageLoader
    private let recorder = StateRecorder()

    init() {
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        self.dataLoader = dataLoader
        self.imageCache = imageCache
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = MockDataCache()
        }
        self.loader = ImageLoader(pipeline: pipeline)
        self.loader.delegate = recorder
    }

    // MARK: - Order

    @Test func loadReportsStartedAndFinished() async throws {
        // When
        let handle = loader.load(Test.request)
        let response = try await handle.response

        // Then
        #expect(recorder.events.filter { $0 != "progress" } == ["started", "finished(success)"])

        let started = try #require(recorder.states.first)
        #expect(started.isLoading)
        #expect(started.task != nil)
        #expect(started.task === handle.task)
        #expect(started.imageContainer == nil)

        let finished = try #require(recorder.states.last)
        #expect(!finished.isLoading)
        #expect(finished.task == nil)
        #expect(finished.image === response.image)
        #expect(loader.task == nil)
    }

    @Test func nilRequestFinishesSynchronously() async throws {
        // When
        let handle = loader.load(nil as ImageRequest?)

        // Then
        #expect(recorder.events == ["finished(failure, sync)"])
        #expect(handle.task == nil)
        #expect(loader.state.error == .imageRequestMissing)
        let result = await handle.result
        #expect(result.error == .imageRequestMissing)
    }

    @Test func memoryCacheHitFinishesSynchronously() async throws {
        // Given
        imageCache[Test.request] = Test.container

        // When
        let handle = loader.load(Test.request)

        // Then
        #expect(recorder.events == ["finished(success, sync)"])
        #expect(handle.task == nil)
        #expect(loader.state.image != nil)
        #expect(dataLoader.createdTaskCount == 0)
        let response = try await handle.response
        #expect(response.cacheType == .memory)
    }

    @Test func cachedPreviewIsTheImageWhileLoading() throws {
        // Given
        dataLoader.isSuspended = true
        let preview = ImageContainer(image: Test.image, isPreview: true)
        imageCache[Test.request] = preview

        // When
        loader.load(Test.request)

        // Then
        #expect(recorder.events == ["started"])
        let state = try #require(recorder.states.last)
        #expect(state.image === preview.image)
        #expect(!state.isPreviousImage)
        #expect(state.isLoading)
    }

    @Test func progressivePreviewsAreReported() async throws {
        // Given
        let progressiveLoader = MockProgressiveDataLoader()
        loader.pipeline = progressiveLoader.makePipeline()
        recorder.onUpdate = { state in
            if case .preview = state.event {
                #expect(state.image != nil)
                #expect(state.isLoading)
                progressiveLoader.resume()
            }
        }

        // When
        _ = try await loader.load(Test.request).response

        // Then
        #expect(recorder.events.contains("preview"))
        #expect(recorder.events.last == "finished(success)")
    }

    @Test func progressivePreviewsAreNotReportedWhenDisabled() async throws {
        // Given
        let progressiveLoader = MockProgressiveDataLoader()
        loader.pipeline = progressiveLoader.makePipeline()
        loader.isProgressiveRenderingEnabled = false
        progressiveLoader.resumeServingChunks(3)

        // When
        _ = try await loader.load(Test.request).response

        // Then
        #expect(!recorder.events.contains("preview"))
    }

    // MARK: - Cancellation

    @Test func newLoadCancelsThePreviousOne() async throws {
        // Given
        dataLoader.isSuspended = true
        let first = loader.load(Test.request)

        // When
        let second = loader.load(URL(string: "https://example.com/other.jpg")!)

        // Then
        #expect(await first.result.error == .cancelled)
        #expect(first.task?.isCancelled == true)
        #expect(loader.task === second.task)
        #expect(recorder.events == ["started", "started"])
    }

    @Test func cancelReportsCancelled() async throws {
        // Given
        dataLoader.isSuspended = true
        let handle = loader.load(Test.request)

        // When
        loader.cancel()

        // Then
        #expect(recorder.events == ["started", "cancelled"])
        #expect(!loader.state.isLoading)
        #expect(loader.task == nil)
        #expect(handle.task?.isCancelled == true)
        #expect(await handle.result.error == .cancelled)
    }

    @Test func cancelWithoutLoadDoesNothing() {
        // When
        loader.cancel()

        // Then
        #expect(recorder.events.isEmpty)
    }

    @Test func cancellingTheAwaitingTaskCancelsTheLoad() async throws {
        // Given
        dataLoader.isSuspended = true
        let handle = loader.load(Test.request)

        // When
        let task = Task { await handle.result }
        task.cancel()
        let result = await task.value

        // Then
        #expect(result.error == .cancelled)
        #expect(handle.task?.isCancelled == true)
        #expect(!loader.state.isLoading)
        #expect(recorder.events == ["started", "cancelled"])
    }

    @Test func cancellingTheAwaitingTaskDoesNotCancelTheNextLoad() async throws {
        // Given a load that was replaced
        dataLoader.isSuspended = true
        let first = loader.load(Test.request)
        let second = loader.load(URL(string: "https://example.com/other.jpg")!)

        // When
        first.cancel()

        // Then
        #expect(loader.task === second.task)
        #expect(second.task?.isCancelled == false)
    }

    @Test func cancellingTheImageTaskCancelsTheLoad() async throws {
        // Given
        dataLoader.isSuspended = true
        let handle = loader.load(Test.request)

        // When
        handle.task?.cancel()
        let result = await handle.result

        // Then
        #expect(result.error == .cancelled)
        #expect(!loader.state.isLoading)
        #expect(loader.task == nil)
        #expect(recorder.events == ["started", "cancelled"])
    }

    @Test func resetClearsTheState() {
        // Given
        imageCache[Test.request] = Test.container
        loader.load(Test.request)

        // When
        loader.reset()

        // Then
        #expect(recorder.events.last == "reset")
        #expect(loader.state.imageContainer == nil)
        #expect(loader.state.result == nil)
        #expect(loader.state.request == nil)
    }

    @Test func deallocatingTheLoaderCancelsTheLoad() async throws {
        // Given
        dataLoader.isSuspended = true
        var loader: ImageLoader? = ImageLoader(pipeline: pipeline)
        let handle = try #require(loader?.load(Test.request))

        // When
        loader = nil

        // Then
        #expect(handle.task?.isCancelled == true)
        #expect(await handle.result.error == .cancelled)
    }

    // MARK: - Keeping the Previous Image

    @Test func previousImageIsKeptWhileLoading() async throws {
        // Given
        loader.keepsPreviousImage = true
        imageCache[Test.request] = Test.container
        loader.load(Test.request)
        let previous = try #require(loader.state.image)

        // When
        dataLoader.isSuspended = true
        loader.load(URL(string: "https://example.com/other.jpg")!)

        // Then
        #expect(loader.state.image === previous)
        #expect(loader.state.isPreviousImage)

        // When the new image arrives
        dataLoader.isSuspended = false
        let response = try await loader.load(URL(string: "https://example.com/other.jpg")!).response

        // Then it replaces the previous one
        #expect(loader.state.image === response.image)
        #expect(!loader.state.isPreviousImage)
    }

    @Test func previousImageIsDroppedWhenLoadFails() async throws {
        // Given
        loader.keepsPreviousImage = true
        imageCache[Test.request] = Test.container
        loader.load(Test.request)

        let otherURL = URL(string: "https://example.com/other.jpg")!
        dataLoader.results[otherURL] = .failure(NSError(domain: "test", code: 42))

        // When
        _ = await loader.load(otherURL).result

        // Then
        #expect(loader.state.imageContainer == nil)
        #expect(!loader.state.isPreviousImage)
    }

    @Test func previousImageIsDroppedForNilRequest() {
        // Given
        loader.keepsPreviousImage = true
        imageCache[Test.request] = Test.container
        loader.load(Test.request)

        // When
        loader.load(nil as ImageRequest?)

        // Then
        #expect(loader.state.imageContainer == nil)
    }

    // MARK: - Options

    @Test func priorityUpdatesTheRunningTask() throws {
        // Given
        dataLoader.isSuspended = true
        loader.load(Test.request)
        let task = try #require(loader.task)

        // When
        loader.priority = .high

        // Then
        #expect(task.priority == .high)

        // When
        loader.priority = nil

        // Then it's back to the priority of the request
        #expect(task.priority == .normal)
    }

    @Test func processorsAreAppliedToRequestsWithoutTheirOwn() throws {
        // Given
        dataLoader.isSuspended = true
        loader.processors = [ImageProcessors.Resize(width: 100)]

        // When
        loader.load(Test.request)

        // Then
        let task = try #require(loader.task)
        #expect(task.request.processors.count == 1)
    }

    // MARK: - Loading From a Closure

    @Test func closureLoadReportsStartedAndFinished() async throws {
        // When
        let handle = loader.load { Test.response }

        // Then it has started, and has neither a task nor a request
        #expect(recorder.events == ["started"])
        let started = try #require(recorder.states.first)
        #expect(started.isLoading)
        #expect(started.task == nil)
        #expect(started.request == nil)
        #expect(handle.task == nil)
        if case .started(let task) = started.event {
            #expect(task == nil)
        } else {
            Issue.record("Expected the started event")
        }

        // When
        let response = try await handle.response

        // Then
        #expect(recorder.events == ["started", "finished(success)"])
        let finished = try #require(recorder.states.last)
        #expect(!finished.isLoading)
        #expect(finished.image === response.image)
        #expect(finished.result?.error == nil)
    }

    @Test func closureLoadStartsAfterTheLoadReturns() async throws {
        // Given
        let ran = Ref(false)

        // When
        let handle = loader.load {
            ran.value = true
            return Test.response
        }

        // Then
        #expect(!ran.value)
        #expect(loader.state.isLoading)
        _ = try await handle.response
        #expect(ran.value)
    }

    @Test func closureLoadWrapsAnyError() async {
        // Given
        struct LoadError: Error {}

        // When
        let result = await loader.load { throw LoadError() }.result

        // Then
        guard case .dataLoadingFailed(let error) = result.error else {
            Issue.record("Expected dataLoadingFailed, got \(String(describing: result.error))")
            return
        }
        #expect(error is LoadError)
        #expect(loader.state.error == result.error)
        #expect(recorder.events == ["started", "finished(failure)"])
    }

    @Test func closureLoadPreservesPipelineError() async {
        // When
        let result = await loader.load { throw ImagePipeline.Error.dataDownloadExceededMaximumSize }.result

        // Then
        #expect(result.error == .dataDownloadExceededMaximumSize)
    }

    @Test func cancelStopsAClosureLoad() async {
        // Given
        let gate = AsyncGate()
        let started = TestExpectation()
        let handle = loader.load {
            started.fulfill()
            await gate.wait()
            return Test.response
        }
        await started.wait()

        // When
        loader.cancel()

        // Then
        #expect(recorder.events == ["started", "cancelled"])
        #expect(!loader.state.isLoading)
        #expect(await handle.result.error == .cancelled)
        gate.open()
    }

    @Test func cancelCancelsTheSwiftTaskOfAClosureLoad() async throws {
        // Given an action that stops when it's cancelled
        let started = TestExpectation()
        let stopped = Ref<Bool?>(nil)
        loader.load {
            started.fulfill()
            do {
                try await Task.sleep(for: .seconds(60))
                stopped.value = false
            } catch {
                stopped.value = true
                throw error
            }
            return Test.response
        }
        await started.wait()

        // When
        loader.cancel()
        await drainPendingWork()

        // Then
        #expect(stopped.value == true)
        #expect(recorder.events == ["started", "cancelled"])
    }

    @Test func closureLoadDeliversNoResultAfterCancel() async {
        // Given an action that ignores cancellation, like most non-Nuke async work
        let gate = AsyncGate()
        let started = TestExpectation()
        let actionReturned = TestExpectation()
        loader.load {
            started.fulfill()
            await gate.wait()
            actionReturned.fulfill()
            return Test.response
        }
        await started.wait()

        // When
        loader.cancel()
        gate.open()
        await actionReturned.wait()
        await drainPendingWork()

        // Then
        #expect(recorder.events == ["started", "cancelled"])
        #expect(loader.state.result == nil)
        #expect(loader.state.imageContainer == nil)
    }

    @Test func resetDiscardsAClosureLoad() async {
        // Given
        let gate = AsyncGate()
        let started = TestExpectation()
        let actionReturned = TestExpectation()
        let handle = loader.load {
            started.fulfill()
            await gate.wait()
            actionReturned.fulfill()
            return Test.response
        }
        await started.wait()

        // When
        loader.reset()
        gate.open()
        await actionReturned.wait()
        await drainPendingWork()

        // Then
        #expect(recorder.events == ["started", "reset"])
        #expect(loader.state.result == nil)
        #expect(await handle.result.error == .cancelled)
    }

    @Test func newLoadReplacesAClosureLoad() async throws {
        // Given
        let gate = AsyncGate()
        let started = TestExpectation()
        let actionReturned = TestExpectation()
        let first = loader.load {
            started.fulfill()
            await gate.wait()
            actionReturned.fulfill()
            return ImageResponse(container: ImageContainer(image: PlatformImage()), request: Test.request)
        }
        await started.wait()

        // When
        let second = loader.load { Test.response }
        let response = try await second.response
        gate.open()
        await actionReturned.wait()
        await drainPendingWork()

        // Then the late result of the first load doesn't overwrite the second
        #expect(await first.result.error == .cancelled)
        #expect(loader.state.image === response.image)
        #expect(recorder.events == ["started", "started", "finished(success)"])
    }

    @Test func pipelineLoadReplacesAClosureLoad() async throws {
        // Given
        let gate = AsyncGate()
        let started = TestExpectation()
        let first = loader.load {
            started.fulfill()
            await gate.wait()
            return Test.response
        }
        await started.wait()

        // When
        let response = try await loader.load(Test.request).response
        gate.open()
        await drainPendingWork()

        // Then
        #expect(await first.result.error == .cancelled)
        #expect(loader.state.image === response.image)
        #expect(loader.state.request?.url == Test.url)
    }

    @Test func closureLoadReplacesAPipelineLoad() async throws {
        // Given
        dataLoader.isSuspended = true
        let first = loader.load(Test.request)

        // When
        let response = try await loader.load { Test.response }.response

        // Then
        #expect(first.task?.isCancelled == true)
        #expect(await first.result.error == .cancelled)
        #expect(loader.state.image === response.image)
        #expect(loader.state.request == nil)
        #expect(loader.task == nil)
    }

    @Test func cancellingTheAwaitingTaskCancelsAClosureLoad() async {
        // Given
        let gate = AsyncGate()
        let started = TestExpectation()
        let handle = loader.load {
            started.fulfill()
            await gate.wait()
            return Test.response
        }
        await started.wait()

        // When
        let task = Task { await handle.result }
        task.cancel()
        let result = await task.value

        // Then
        #expect(result.error == .cancelled)
        #expect(!loader.state.isLoading)
        #expect(recorder.events == ["started", "cancelled"])
        gate.open()
    }

    @Test func deallocatingTheLoaderCancelsAClosureLoad() async throws {
        // Given
        let started = TestExpectation()
        let stopped = TestExpectation()
        var loader: ImageLoader? = ImageLoader(pipeline: pipeline)
        let handle = try #require(loader?.load {
            started.fulfill()
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                stopped.fulfill()
                throw error
            }
            return Test.response
        })
        await started.wait()

        // When
        loader = nil

        // Then
        await stopped.wait()
        #expect(await handle.result.error == .cancelled)
    }

    @Test func previousImageIsKeptWhileAClosureLoads() async throws {
        // Given
        loader.keepsPreviousImage = true
        imageCache[Test.request] = Test.container
        loader.load(Test.request)
        let previous = try #require(loader.state.image)

        // When
        let gate = AsyncGate()
        let handle = loader.load {
            await gate.wait()
            return ImageResponse(container: ImageContainer(image: PlatformImage()), request: Test.request)
        }

        // Then
        #expect(loader.state.image === previous)
        #expect(loader.state.isPreviousImage)

        // When the new image arrives
        gate.open()
        let response = try await handle.response

        // Then it replaces the previous one
        #expect(loader.state.image === response.image)
        #expect(!loader.state.isPreviousImage)
    }

    @Test func previousImageIsDroppedWhenAClosureLoadFails() async {
        // Given
        struct LoadError: Error {}
        loader.keepsPreviousImage = true
        imageCache[Test.request] = Test.container
        loader.load(Test.request)

        // When
        _ = await loader.load { throw LoadError() }.result

        // Then
        #expect(loader.state.imageContainer == nil)
        #expect(!loader.state.isPreviousImage)
    }

    // MARK: - Delegate

    @Test func loadStartedFromTheDelegateIsNotFollowedByAStaleState() async throws {
        // Given
        let fallbackURL = URL(string: "https://example.com/fallback.jpg")!
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))
        var tags: [String] = []
        loader.onUpdate = { [loader] state in
            tags.append(state.event.tag)
            if case .finished(.failure, _) = state.event {
                dataLoader.isSuspended = true
                loader.load(fallbackURL)
            }
        }

        // When
        _ = await loader.load(Test.url).result

        // Then the delegate is told about the fallback, and not about the
        // failure that came before it
        #expect(tags == ["started", "finished(failure)", "started"])
        #expect(recorder.events == ["started", "started"])
        #expect(loader.task?.request.url == fallbackURL)
    }

    // MARK: - Loading Into Objects

    @Test func loadIntoObjectRendersTheStates() async throws {
        // Given
        let target = Target()

        // When
        let response = try await ImageLoader.load(Test.request, into: target, pipeline: pipeline) { target, state in
            target.events.append(state.event.tag)
        }.response

        // Then
        #expect(target.events.filter { $0 != "progress" } == ["started", "finished(success)"])
        #expect(ImageLoader.loader(for: target).state.image === response.image)
    }

    @Test func loadIntoObjectCancelsThePreviousLoad() async throws {
        // Given
        dataLoader.isSuspended = true
        let target = Target()
        let first = ImageLoader.load(Test.request, into: target, pipeline: pipeline) { _, _ in }

        // When
        ImageLoader.load(URL(string: "https://example.com/other.jpg")!, into: target) { _, _ in }

        // Then
        #expect(await first.result.error == .cancelled)
        #expect(ImageLoader.loader(for: target).pipeline === pipeline)
    }

    @Test func loadIntoObjectDoesNotRetainIt() throws {
        // Given
        dataLoader.isSuspended = true
        weak var weakTarget: Target?
        var handle: ImageLoader.Handle?

        // When
        do {
            let target = Target()
            weakTarget = target
            handle = ImageLoader.load(Test.request, into: target, pipeline: pipeline) { target, _ in
                target.events.append("update")
            }
        }

        // Then the target is gone, and so is its load
        #expect(weakTarget == nil)
        let task = try #require(handle?.task)
        #expect(task.isCancelled)
    }
}

// MARK: - Helpers

@MainActor
private final class StateRecorder: ImageLoaderDelegate {
    var states: [ImageLoader.State] = []
    var onUpdate: ((ImageLoader.State) -> Void)?

    var events: [String] { states.map(\.event.tag) }

    func imageLoader(_ loader: ImageLoader, didUpdate state: ImageLoader.State) {
        states.append(state)
        onUpdate?(state)
    }
}

private final class Target {
    var events: [String] = []
}

extension ImageLoader.Event {
    var tag: String {
        switch self {
        case .started: "started"
        case .progress: "progress"
        case .preview: "preview"
        case let .finished(result, isSync):
            "finished(\(result.error == nil ? "success" : "failure")\(isSync ? ", sync" : ""))"
        case .cancelled: "cancelled"
        case .reset: "reset"
        }
    }
}

extension Result where Failure == ImagePipeline.Error {
    var error: ImagePipeline.Error? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
