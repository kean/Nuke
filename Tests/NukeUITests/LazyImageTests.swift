// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import SwiftUI
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

@Suite(.serialized, .timeLimit(.minutes(5))) @MainActor
struct LazyImageTests {
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
            $0.dataCache = MockDataCache()
        }
    }

    // MARK: - Loading

    @Test func imageLoadedOnAppear() async throws {
        let completed = TestExpectation()
        let result = Ref<Result<ImageResponse, Error>?>(nil)

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onCompletion {
                    result.value = $0
                    completed.fulfill()
                }
        }
        await completed.wait()

        #expect(try #require(result.value).isSuccess)
        withExtendedLifetime(host) {}
    }

    @Test func imageLoadedWithRequest() async throws {
        let completed = TestExpectation()
        let result = Ref<Result<ImageResponse, Error>?>(nil)

        let host = ViewHost(Test.request) { request in
            LazyImage(request: request)
                .pipeline(pipeline)
                .onCompletion {
                    result.value = $0
                    completed.fulfill()
                }
        }
        await completed.wait()

        #expect(try #require(result.value).isSuccess)
        withExtendedLifetime(host) {}
    }

    @Test func nilURLFailsWithRequestMissing() async throws {
        let completed = TestExpectation()
        let result = Ref<Result<ImageResponse, Error>?>(nil)

        let host = ViewHost(nil as URL?) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onCompletion {
                    result.value = $0
                    completed.fulfill()
                }
        }
        await completed.wait()

        let received = try #require(result.value)
        let error = try #require(received.error as? ImagePipeline.Error)
        #expect(error == .imageRequestMissing)
        withExtendedLifetime(host) {}
    }

    @Test func nilRequestFailsWithRequestMissing() async throws {
        let completed = TestExpectation()
        let result = Ref<Result<ImageResponse, Error>?>(nil)

        let host = ViewHost(nil as ImageRequest?) { request in
            LazyImage(request: request)
                .pipeline(pipeline)
                .onCompletion {
                    result.value = $0
                    completed.fulfill()
                }
        }
        await completed.wait()

        let received = try #require(result.value)
        let error = try #require(received.error as? ImagePipeline.Error)
        #expect(error == .imageRequestMissing)
        withExtendedLifetime(host) {}
    }

    // MARK: - Content

    @Test func contentClosureObservesLoadingThenImage() async {
        let completed = TestExpectation()
        let states = Ref<[(isLoading: Bool, hasImage: Bool)]>([])

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url) { state in
                let _ = states.value.append((state.isLoading, state.image != nil))
                Color.clear
            }
            .pipeline(pipeline)
            .onCompletion { _ in completed.fulfill() }
        }
        await completed.wait()
        await host.render(until: { states.value.contains { !$0.isLoading && $0.hasImage } })

        #expect(states.value.contains { $0.isLoading && !$0.hasImage })
        #expect(states.value.contains { !$0.isLoading && $0.hasImage })
    }

    @Test func contentClosureObservesError() async {
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))

        let completed = TestExpectation()
        let sawError = Ref(false)

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url) { state in
                let _ = { if state.error != nil { sawError.value = true } }()
                Color.clear
            }
            .pipeline(pipeline)
            .onCompletion { _ in completed.fulfill() }
        }
        await completed.wait()
        await host.render(until: { sawError.value })

        #expect(sawError.value)
    }

    @Test func nilURLWithContentClosureReportsErrorToContent() async throws {
        let completed = TestExpectation()
        let result = Ref<Result<ImageResponse, Error>?>(nil)
        let sawError = Ref(false)

        let host = ViewHost(nil as URL?) { url in
            LazyImage(url: url, transaction: Transaction(animation: .default)) { state in
                let _ = { if state.error != nil { sawError.value = true } }()
                Color.clear
            }
            .pipeline(pipeline)
            .onCompletion {
                result.value = $0
                completed.fulfill()
            }
        }
        await completed.wait()
        await host.render(until: { sawError.value })

        let received = try #require(result.value)
        let error = try #require(received.error as? ImagePipeline.Error)
        #expect(error == .imageRequestMissing)
        #expect(sawError.value)
    }

    @Test func defaultContentIsRendered() async {
        // The default content has no observable state, so this only verifies
        // that the view builds it and the request completes.
        let completed = TestExpectation()

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onCompletion { _ in completed.fulfill() }
        }
        await completed.wait()
        await host.render()

        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Memory Cache

    @Test func memoryCacheHitCompletesWithoutDownloading() async throws {
        pipeline.cache[Test.request] = Test.container

        let result = Ref<Result<ImageResponse, Error>?>(nil)
        let host = ViewHost(Test.request) { request in
            LazyImage(request: request)
                .pipeline(pipeline)
                .onCompletion { result.value = $0 }
        }
        await host.render(until: { result.value != nil })

        let received = try #require(result.value)
        let response = try #require(received.value)
        #expect(response.cacheType == .memory)
        #expect(dataLoader.createdTaskCount == 0)
    }

    // MARK: - Callbacks

    @Test func onStartCalled() async throws {
        dataLoader.isSuspended = true

        let started = TestExpectation()
        let task = Ref<ImageTask?>(nil)

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onStart {
                    task.value = $0
                    started.fulfill()
                }
        }
        await started.wait()

        _ = try #require(task.value)
        withExtendedLifetime(host) {}
    }

    // MARK: - Pipeline

    @Test func customPipelineIsUsed() async {
        let customDataLoader = MockDataLoader()
        let customPipeline = ImagePipeline {
            $0.dataLoader = customDataLoader
            $0.imageCache = nil
        }

        let completed = TestExpectation()
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(customPipeline)
                .onCompletion { _ in completed.fulfill() }
        }
        await completed.wait()

        #expect(customDataLoader.createdTaskCount == 1)
        #expect(dataLoader.createdTaskCount == 0)
        withExtendedLifetime(host) {}
    }

    // MARK: - Processors

    @Test func processorsApplied() async {
        let completed = TestExpectation()
        let response = Ref<ImageResponse?>(nil)

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .processors([MockImageProcessor(id: "p1")])
                .onCompletion {
                    response.value = $0.value
                    completed.fulfill()
                }
        }
        await completed.wait()

        #expect(response.value?.image.nk_test_processorIDs == ["p1"])
        withExtendedLifetime(host) {}
    }

    @Test func nilProcessorsKeepRequestProcessors() async {
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        let completed = TestExpectation()
        let response = Ref<ImageResponse?>(nil)

        let host = ViewHost(request) { request in
            LazyImage(request: request)
                .pipeline(pipeline)
                .processors(nil)
                .onCompletion {
                    response.value = $0.value
                    completed.fulfill()
                }
        }
        await completed.wait()

        #expect(response.value?.image.nk_test_processorIDs == ["p1"])
        withExtendedLifetime(host) {}
    }

    @Test func processorsFromRequestTakePrecedenceOverViewProcessors() async {
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p2")])

        let completed = TestExpectation()
        let response = Ref<ImageResponse?>(nil)

        let host = ViewHost(request) { request in
            LazyImage(request: request)
                .pipeline(pipeline)
                .processors([MockImageProcessor(id: "p1")])
                .onCompletion {
                    response.value = $0.value
                    completed.fulfill()
                }
        }
        await completed.wait()

        #expect(response.value?.image.nk_test_processorIDs == ["p2"])
        withExtendedLifetime(host) {}
    }

    // MARK: - Priority

    @Test func priorityApplied() async throws {
        dataLoader.isSuspended = true

        let started = TestExpectation()
        let task = Ref<ImageTask?>(nil)

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .priority(.high)
                .onStart {
                    task.value = $0
                    started.fulfill()
                }
        }
        await started.wait()

        #expect(try #require(task.value).priority == .high)
        withExtendedLifetime(host) {}
    }

    @Test func nilPriorityKeepsRequestPriority() async throws {
        dataLoader.isSuspended = true

        let started = TestExpectation()
        let task = Ref<ImageTask?>(nil)

        let request = ImageRequest(url: Test.url, priority: .high)
        let host = ViewHost(request) { request in
            LazyImage(request: request)
                .pipeline(pipeline)
                .priority(nil)
                .onStart {
                    task.value = $0
                    started.fulfill()
                }
        }
        await started.wait()

        #expect(try #require(task.value).priority == .high)
        withExtendedLifetime(host) {}
    }

    // MARK: - Disappear Behavior

    @Test func requestCancelledOnDisappearByDefault() async throws {
        dataLoader.isSuspended = true

        let started = TestExpectation()
        let task = Ref<ImageTask?>(nil)
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onStart {
                    task.value = $0
                    started.fulfill()
                }
        }
        await started.wait()

        let imageTask = try #require(task.value)
        #expect(imageTask.state == .running)

        await host.hideContent(until: { imageTask.state == .cancelled })

        #expect(imageTask.state == .cancelled)
    }

    @Test func requestCancelledWhenViewIsRemovedFromHierarchy() async throws {
        dataLoader.isSuspended = true

        let started = TestExpectation()
        let task = Ref<ImageTask?>(nil)
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onDisappear(nil)
                .onStart {
                    task.value = $0
                    started.fulfill()
                }
        }
        await started.wait()

        let imageTask = try #require(task.value)
        await host.removeContent(until: { imageTask.state == .cancelled })

        // The view model is released with the view, and its deinit cancels the task.
        #expect(imageTask.state == .cancelled)
    }

    @Test func requestPriorityLoweredOnDisappear() async throws {
        dataLoader.isSuspended = true

        let started = TestExpectation()
        let task = Ref<ImageTask?>(nil)
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onDisappear(.lowerPriority)
                .onStart {
                    task.value = $0
                    started.fulfill()
                }
        }
        await started.wait()

        let imageTask = try #require(task.value)
        #expect(imageTask.priority == .normal)

        await host.hideContent(until: { imageTask.priority == .veryLow })

        #expect(imageTask.priority == .veryLow)
        #expect(imageTask.state == .running)
    }

    @Test func requestNotCancelledWhenDisappearBehaviorIsNil() async throws {
        dataLoader.isSuspended = true

        let started = TestExpectation()
        let task = Ref<ImageTask?>(nil)
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onDisappear(nil)
                .onStart {
                    task.value = $0
                    started.fulfill()
                }
        }
        await started.wait()

        let imageTask = try #require(task.value)
        await host.hideContent()

        #expect(imageTask.priority == .normal)
        #expect(imageTask.state == .running)
    }

    @Test func priorityRestoredWhenViewReappears() async throws {
        dataLoader.isSuspended = true

        let started = TestExpectation()
        let tasks = Ref<[ImageTask]>([])
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onDisappear(.lowerPriority)
                .onStart {
                    tasks.value.append($0)
                    started.fulfill()
                }
        }
        await started.wait()

        let firstTask = try #require(tasks.value.last)
        await host.hideContent(until: { firstTask.priority == .veryLow })
        #expect(firstTask.priority == .veryLow)

        // Reappearing restarts the request. The lowered priority must be undone
        // so that the new request uses its own priority again.
        await host.showContent(until: { tasks.value.count > 1 })

        let secondTask = try #require(tasks.value.last)
        #expect(secondTask !== firstTask)
        #expect(secondTask.priority == .normal)
    }

    // MARK: - Request Changes

    @Test func newRequestStartedWhenURLChanges() async {
        let completions = Ref(0)
        let first = TestExpectation()
        let second = TestExpectation()

        let otherURL = URL(string: "https://example.com/other.jpeg")!
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onCompletion { _ in
                    completions.value += 1
                    if completions.value == 1 { first.fulfill() } else { second.fulfill() }
                }
        }
        await first.wait()

        await host.update(otherURL)
        await second.wait()

        #expect(completions.value == 2)
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func noNewRequestWhenRequestIsUnchanged() async {
        let completions = Ref(0)
        let first = TestExpectation()

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onCompletion { _ in
                    completions.value += 1
                    if completions.value == 1 { first.fulfill() }
                }
        }
        await first.wait()

        // Re-render with an equal request: the context is unchanged, so
        // `onChange` must not fire and no new load may start.
        await host.update(Test.url)
        await host.render()

        #expect(completions.value == 1)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func newRequestStartedWhenProcessorsChange() async {
        let completions = Ref(0)
        let first = TestExpectation()
        let second = TestExpectation()

        let host = ViewHost([MockImageProcessor(id: "p1")] as [any ImageProcessing]) { processors in
            LazyImage(url: Test.url)
                .pipeline(pipeline)
                .processors(processors)
                .onCompletion { _ in
                    completions.value += 1
                    if completions.value == 1 { first.fulfill() } else { second.fulfill() }
                }
        }
        await first.wait()

        await host.update([MockImageProcessor(id: "p2")])
        await second.wait()

        #expect(completions.value == 2)
    }

    @Test func newRequestStartedWhenPriorityChanges() async {
        let completions = Ref(0)
        let first = TestExpectation()
        let second = TestExpectation()

        let host = ViewHost(ImageRequest.Priority.normal) { priority in
            LazyImage(url: Test.url)
                .pipeline(pipeline)
                .priority(priority)
                .onCompletion { _ in
                    completions.value += 1
                    if completions.value == 1 { first.fulfill() } else { second.fulfill() }
                }
        }
        await first.wait()

        await host.update(.high)
        await second.wait()

        #expect(completions.value == 2)
    }
}

#endif
