// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import SwiftUI
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

// BUG: `LazyImage.onAppear()` (Sources/NukeUI/LazyImage.swift:181-190)
// unconditionally calls `viewModel.load(context?.request)`, and
// `FetchImage.load(_:)` starts with `cancel()`. So every time the view comes
// back on screen, the request that is still running is cancelled and started
// over – including the ones the disappear behavior deliberately kept alive:
//
// - `.onDisappear(nil)` – documented as "Pass `nil` to disable any behavior
//   on disappear" – the request keeps running off screen, then is thrown
//   away the moment the view reappears.
// - `.onDisappear(.lowerPriority)` – "Lowers the request's priority to very
//   low" – whose only point over `.cancel` is to let the download continue.
//
// With a single subscriber, cancelling the `ImageTask` terminates the whole
// task graph (AsyncTask.unsubsribe -> terminate(.cancelled)), so the
// in-flight data task is cancelled and a new one is created: the bytes that
// were downloaded while the view was off screen are lost.
//
// Expected: the running request is kept (its priority restored), no second
// data task is created.
// Actual: the first ImageTask is cancelled, a new one starts, and the data
// loader creates a second data task for the same URL.
//
// The same unconditional reload also double-starts a request: if the request
// changes while the view is off screen, SwiftUI delivers both `onAppear` and
// `onChange(of: context)` when it comes back, and each calls `load`, so the
// new request is started, cancelled, and started again.
@Suite(.serialized, .timeLimit(.minutes(5))) @MainActor
struct LazyImageReappearRestartsLiveRequestBugRepro {
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
        }
    }

    @Test func reappearingKeepsTheRequestThatDisappearBehaviorNilKeptAlive() async throws {
        dataLoader.isSuspended = true
        let dataTaskStarted = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)

        let tasks = Ref<[ImageTask]>([])
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onDisappear(nil)
                .onStart { tasks.value.append($0) }
        }
        await dataTaskStarted.wait()
        let firstTask = try #require(tasks.value.first)

        await host.hideContent()
        #expect(!firstTask.isCancelled) // Kept alive off screen, as documented

        await host.showContent(until: { tasks.value.count > 1 })

        // Expected: not cancelled, 1 task. Actual: cancelled, 2 tasks.
        #expect(!firstTask.isCancelled)
        #expect(tasks.value.count == 1)
    }

    @Test func reappearingKeepsTheRequestWithLoweredPriority() async throws {
        dataLoader.isSuspended = true
        let dataTaskStarted = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)

        let tasks = Ref<[ImageTask]>([])
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onDisappear(.lowerPriority)
                .onStart { tasks.value.append($0) }
        }
        await dataTaskStarted.wait()
        let firstTask = try #require(tasks.value.first)

        await host.hideContent(until: { firstTask.priority == .veryLow })

        // The in-flight data task gets cancelled when the view comes back.
        let dataTaskCancelled = TestExpectation(notification: MockDataLoader.DidCancelTask, object: dataLoader)
        await host.showContent(until: { tasks.value.count > 1 })

        // Expected: not cancelled, 1 task. Actual: cancelled, 2 tasks.
        #expect(!firstTask.isCancelled)
        #expect(tasks.value.count == 1)
        guard firstTask.isCancelled else { return }

        // And the download starts from scratch.
        await dataTaskCancelled.wait()
        let secondDataTask = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        if dataLoader.createdTaskCount < 2 { await secondDataTask.wait() }
        #expect(dataLoader.createdTaskCount == 1) // Actual: 2
    }

    @Test func requestChangedOffScreenIsStartedOnceOnReappear() async throws {
        let otherURL = URL(string: "https://example.com/other.jpeg")!
        let started = Ref<[ImageTask]>([])
        let completions = Ref(0)
        let first = TestExpectation()
        let second = TestExpectation()
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .onStart { started.value.append($0) }
                .onCompletion { _ in
                    completions.value += 1
                    if completions.value == 1 { first.fulfill() } else { second.fulfill() }
                }
        }
        await first.wait()

        await host.hideContent()
        await host.update(otherURL)
        await host.showContent(until: { started.value.count >= 3 })
        await second.wait()

        let tasksForOtherURL = started.value.filter { $0.request.url == otherURL }
        // Expected: 1. Actual: 2, the first of which is cancelled right away.
        #expect(tasksForOtherURL.count == 1)
        #expect(!tasksForOtherURL.contains { $0.isCancelled })
    }
}

#endif
