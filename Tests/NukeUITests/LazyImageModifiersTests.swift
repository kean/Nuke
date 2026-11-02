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
struct LazyImageModifiersTests {
    let dataLoader: MockDataLoader
    let imageCache: MockImageCache
    let pipeline: ImagePipeline

    private let otherURL = URL(string: "https://example.com/other.jpeg")!
    private let failure: Result<(Data, URLResponse), NSError> = .failure(NSError(domain: "test", code: 1))
    private let transitionAnimation = Animation.linear(duration: 0.05)

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
    }

    // MARK: - Reload From the State

    /// What a "Retry" button in the failure content does, rendered: the view
    /// fails, the button's action runs, and the same view shows the image.
    @Test func reloadFromTheFailureViewDisplaysTheImage() async throws {
        dataLoader.results[Test.url] = failure
        let failed = TestExpectation()
        let reloadable = Ref<(any LazyImageState)?>(nil)
        let displayed = Ref<[String]>([])

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url) { (state: LazyImageState) in
                if state.image != nil {
                    SwiftUI.Color.red.onAppear { displayed.value.append("image") }
                } else {
                    SwiftUI.Color.blue
                }
            }
            .pipeline(pipeline)
            .failureView { state in
                let _ = reloadable.value = state
                SwiftUI.Color.green.onAppear {
                    displayed.value.append("failure")
                    failed.fulfill()
                }
            }
        }
        await failed.wait()

        dataLoader.results[Test.url] = nil
        try #require(reloadable.value).reload()
        await host.render(until: { displayed.value.contains("image") })

        #expect(displayed.value == ["failure", "image"])
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func reloadFromTheContentClosureLoadsAgain() async throws {
        dataLoader.results[Test.url] = failure
        let reloadable = Ref<(any LazyImageState)?>(nil)
        let results = Ref<[Bool]>([])

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url) { (state: LazyImageState) in
                let _ = reloadable.value = state
                SwiftUI.Color.blue
            }
            .pipeline(pipeline)
            .onCompletion { results.value.append($0.isSuccess) }
        }
        await host.render(until: { results.value == [false] })

        dataLoader.results[Test.url] = nil
        try #require(reloadable.value).reload()
        await host.render(until: { results.value == [false, true] })

        #expect(dataLoader.createdTaskCount == 2)
    }

    // MARK: - Reload With an ID

    @Test func changingTheReloadIDLoadsAgain() async {
        dataLoader.results[Test.url] = failure
        let results = Ref<[Bool]>([])

        let host = ViewHost(0) { attempt in
            LazyImage(url: Test.url)
                .pipeline(pipeline)
                .reload(id: attempt)
                .onCompletion { results.value.append($0.isSuccess) }
        }
        await host.render(until: { results.value == [false] })

        dataLoader.results[Test.url] = nil
        await host.update(1, until: { results.value == [false, true] })

        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func aReloadKeepsTheStateOfTheView() async {
        // What `.id(UUID())` can't do: the view stays, so the image stays.
        let images = Ref<[Bool]>([])
        let results = Ref<[Bool]>([])

        let host = ViewHost(0) { attempt in
            LazyImage(url: Test.url) { (state: LazyImageState) in
                let _ = images.value.append(state.image != nil)
                SwiftUI.Color.blue
            }
            .pipeline(pipeline)
            .keepsPreviousImage()
            .reload(id: attempt)
            .onCompletion { results.value.append($0.isSuccess) }
        }
        await host.render(until: { results.value == [true] })

        images.value = []
        imageCache.removeAll()
        await host.update(1, until: { results.value == [true, true] })

        #expect(!images.value.isEmpty)
        #expect(!images.value.contains(false))
    }

    @Test func noNewRequestWhenTheReloadIDIsUnchanged() async {
        let completed = TestExpectation()

        let host = ViewHost(1) { version in
            LazyImage(url: Test.url)
                .pipeline(pipeline)
                .reload(id: "same")
                .onCompletion { _ in if version == 1 { completed.fulfill() } }
        }
        await completed.wait()

        await host.update(2)

        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func theFirstReloadIDDoesntLoadAgain() async {
        let completions = Ref(0)

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .reload(id: 7)
                .onCompletion { _ in completions.value += 1 }
        }
        await host.render(until: { completions.value == 1 })
        await host.render()

        #expect(completions.value == 1)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func aReloadIDChangingWithTheRequestLoadsOnce() async {
        let results = Ref<[URL?]>([])

        let host = ViewHost((Test.url, 0)) { value in
            LazyImage(url: value.0)
                .pipeline(pipeline)
                .reload(id: value.1)
                .onCompletion { results.value.append((try? $0.get())?.request.url) }
        }
        await host.render(until: { results.value.count == 1 })

        await host.update((otherURL, 1), until: { results.value.count == 2 })
        await host.render()

        #expect(results.value == [Test.url, otherURL])
        #expect(dataLoader.createdTaskCount == 2)
    }

    @Test func aReloadWhileLoadingKeepsTheTask() async {
        dataLoader.isSuspended = true
        let starts = Ref(0)

        let host = ViewHost(0) { attempt in
            LazyImage(url: Test.url)
                .pipeline(pipeline)
                .reload(id: attempt)
                .onStart { _ in starts.value += 1 }
        }
        await host.render(until: { starts.value == 1 })

        await host.update(1)

        #expect(starts.value == 1)
        dataLoader.isSuspended = false
        withExtendedLifetime(host) {}
    }

    /// The action of `onChange(of:)` runs from the previous update, so a reload
    /// that used what it captured would report to the old callbacks.
    @Test func aReloadUsesTheCurrentCallbacks() async {
        let starts = Ref<[Int]>([])
        let completions = Ref<[Int]>([])

        let host = ViewHost(1) { version in
            LazyImage(url: Test.url)
                .pipeline(pipeline)
                .reload(id: version)
                .onStart { _ in starts.value.append(version) }
                .onCompletion { _ in completions.value.append(version) }
        }
        await host.render(until: { completions.value == [1] })

        imageCache.removeAll()
        await host.update(2, until: { completions.value.count == 2 })

        #expect(starts.value == [1, 2])
        #expect(completions.value == [1, 2])
    }

    // MARK: - Keeps Previous Image

    @Test func thePreviousImageStaysWhileANewOneLoads() async {
        let states = Ref<[(url: URL?, isLoading: Bool, hasImage: Bool)]>([])
        let completions = Ref(0)

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url) { (state: LazyImageState) in
                let _ = states.value.append((url, state.isLoading, state.image != nil))
                SwiftUI.Color.blue
            }
            .pipeline(pipeline)
            .keepsPreviousImage()
            .onCompletion { _ in completions.value += 1 }
        }
        await host.render(until: { completions.value == 1 })

        dataLoader.isSuspended = true
        states.value = []
        await host.update(otherURL, until: { dataLoader.createdTaskCount == 2 })
        await host.render(until: { states.value.last?.isLoading == true })

        let latest = states.value.last
        #expect(latest?.url == otherURL)
        #expect(latest?.hasImage == true)
        dataLoader.isSuspended = false
        await host.render(until: { completions.value == 2 })
        #expect(states.value.last?.hasImage == true)
        #expect(states.value.last?.isLoading == false)
        #expect(!states.value.contains { !$0.hasImage })
    }

    /// The control for the test above: this is what the modifier changes.
    @Test func thePreviousImageIsClearedByDefault() async {
        let hasImage = Ref<Bool?>(nil)
        let completions = Ref(0)

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url) { (state: LazyImageState) in
                let _ = hasImage.value = state.image != nil
                SwiftUI.Color.blue
            }
            .pipeline(pipeline)
            .onCompletion { _ in completions.value += 1 }
        }
        await host.render(until: { completions.value == 1 })

        dataLoader.isSuspended = true
        await host.update(otherURL, until: { dataLoader.createdTaskCount == 2 })
        await host.render(until: { hasImage.value == false })

        #expect(hasImage.value == false)
        dataLoader.isSuspended = false
        withExtendedLifetime(host) {}
    }

    @Test func thePreviousImageIsDroppedWhenTheNewLoadFails() async {
        dataLoader.results[otherURL] = failure
        let latest = Ref<(hasImage: Bool, hasError: Bool)?>(nil)
        let completions = Ref(0)

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url) { (state: LazyImageState) in
                let _ = latest.value = (state.image != nil, state.error != nil)
                SwiftUI.Color.blue
            }
            .pipeline(pipeline)
            .keepsPreviousImage()
            .onCompletion { _ in completions.value += 1 }
        }
        await host.render(until: { completions.value == 1 })

        await host.update(otherURL, until: { completions.value == 2 })
        await host.render(until: { latest.value?.hasError == true })

        #expect(latest.value?.hasImage == false)
    }

    /// The modifier changing together with the request applies to that load,
    /// not the next one.
    @Test func keepsPreviousImageIsReadFromTheCurrentView() async {
        let hasImageWhileLoading = Ref<[Bool]>([])
        let completions = Ref(0)

        let host = ViewHost(1) { version in
            LazyImage(url: version == 1 ? Test.url : otherURL) { (state: LazyImageState) in
                if state.isLoading, version == 2 {
                    let _ = hasImageWhileLoading.value.append(state.image != nil)
                }
                SwiftUI.Color.blue
            }
            .pipeline(pipeline)
            .keepsPreviousImage(version == 2)
            .onCompletion { _ in completions.value += 1 }
        }
        await host.render(until: { completions.value == 1 })

        dataLoader.isSuspended = true
        await host.update(2, until: { dataLoader.createdTaskCount == 2 })
        await host.render(until: { !hasImageWhileLoading.value.isEmpty })

        #expect(hasImageWhileLoading.value.last == true)
        dataLoader.isSuspended = false
        await host.render(until: { completions.value == 2 })
    }

    // MARK: - Failure View

    @Test func failureViewReplacesTheContentClosureOnFailure() async {
        dataLoader.results[Test.url] = failure
        let errors = Ref<[ImagePipeline.Error]>([])
        let contentErrors = Ref<[ImagePipeline.Error]>([])

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url) { (state: LazyImageState) in
                let _ = state.error.map { contentErrors.value.append($0) }
                SwiftUI.Color.blue
            }
            .pipeline(pipeline)
            .failureView { state in
                let _ = state.error.map { errors.value.append($0) }
                SwiftUI.Color.green
            }
        }
        await host.render(until: { !errors.value.isEmpty })
        await host.render()

        #expect(contentErrors.value.isEmpty)
        withExtendedLifetime(host) {}
    }

    @Test func failureViewComposesWithTheDefaultContent() async {
        dataLoader.results[Test.url] = failure
        let bodies = Ref(0)

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .failureView { _ in
                    let _ = bodies.value += 1
                    SwiftUI.Color.green
                }
        }
        await host.render(until: { bodies.value > 0 })
        withExtendedLifetime(host) {}
    }

    @Test func failureViewIsNotBuiltOnSuccess() async {
        let bodies = Ref(0)
        let completed = TestExpectation()

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .failureView { _ in
                    let _ = bodies.value += 1
                    SwiftUI.Color.green
                }
                .onCompletion { _ in completed.fulfill() }
        }
        await completed.wait()
        await host.render()

        #expect(bodies.value == 0)
    }

    @Test func failureViewIsGoneOnceANewRequestStarts() async {
        dataLoader.results[Test.url] = failure
        let isFailureDisplayed = Ref(false)
        let contentBodies = Ref(0)

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url) { _ in
                let _ = contentBodies.value += 1
                SwiftUI.Color.blue
            }
            .pipeline(pipeline)
            .failureView { _ in
                SwiftUI.Color.green
                    .onAppear { isFailureDisplayed.value = true }
                    .onDisappear { isFailureDisplayed.value = false }
            }
        }
        await host.render(until: { isFailureDisplayed.value })

        dataLoader.isSuspended = true
        contentBodies.value = 0
        await host.update(otherURL, until: { !isFailureDisplayed.value })

        #expect(contentBodies.value > 0)
        dataLoader.isSuspended = false
        withExtendedLifetime(host) {}
    }

    // MARK: - Modifiers With Closures

    /// Every update makes new closures, and they can't be compared, so none of
    /// them can be what decides that the view changed.
    @Test func noNewRequestWhenTheClosuresOfTheModifiersChange() async {
        let completed = TestExpectation()

        let host = ViewHost(1) { version in
            LazyImage(url: Test.url)
                .pipeline(pipeline)
                .failureView { _ in Text("\(version)") }
                .imageTransition(.opacity)
                .keepsPreviousImage()
                .onCompletion { _ in if version == 1 { completed.fulfill() } }
        }
        await completed.wait()

        await host.update(2)
        await host.update(3)

        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Image Transition

    @Test func transitionRunsWhenADownloadedImageIsDisplayed() async {
        let log = TransitionLog()
        let completed = TestExpectation()

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .imageTransition(log.transition, animation: transitionAnimation)
                .onCompletion { _ in completed.fulfill() }
        }
        await completed.wait()
        await host.render(until: { log.activeCount > 0 })

        #expect(log.activeCount > 0)
    }

    @Test func noTransitionForAnImageFoundInTheMemoryCache() async {
        imageCache[ImageRequest(url: Test.url)] = Test.container
        let log = TransitionLog()
        let completed = TestExpectation()

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .imageTransition(log.transition, animation: transitionAnimation)
                .onCompletion { _ in completed.fulfill() }
        }
        await completed.wait()
        await host.render()

        #expect(dataLoader.createdTaskCount == 0)
        #expect(log.activeCount == 0)
    }

    @Test func transitionForAMemoryCacheHitWhenAskedFor() async {
        imageCache[ImageRequest(url: Test.url)] = Test.container
        let log = TransitionLog()
        let completed = TestExpectation()

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .imageTransition(log.transition, animation: transitionAnimation, onMemoryCacheHit: true)
                .onCompletion { _ in completed.fulfill() }
        }
        await completed.wait()
        await host.render(until: { log.activeCount > 0 })

        #expect(dataLoader.createdTaskCount == 0)
        #expect(log.activeCount > 0)
    }

    /// The previous image goes with the transition as well, which is what makes
    /// a cross-fade between two images.
    @Test func transitionRunsWhenANewImageReplacesThePreviousOne() async {
        let log = TransitionLog()
        let completions = Ref(0)

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(pipeline)
                .keepsPreviousImage()
                .imageTransition(log.transition, animation: transitionAnimation)
                .onCompletion { _ in completions.value += 1 }
        }
        await host.render(until: { completions.value == 1 })
        await settle(log, in: host)

        await host.update(otherURL, until: { completions.value == 2 })
        await host.render(until: { log.activeCount > 0 })

        #expect(log.activeCount > 0)
    }

    /// The transition doesn't depend on the closure having a branch for the
    /// image to go in.
    @Test func transitionRunsForContentWithNoBranches() async {
        let log = TransitionLog()
        let completed = TestExpectation()

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url) { (state: LazyImageState) in
                (state.image ?? Image(systemName: "photo")).resizable()
            }
            .pipeline(pipeline)
            .imageTransition(log.transition, animation: transitionAnimation)
            .onCompletion { _ in completed.fulfill() }
        }
        await completed.wait()
        await host.render(until: { log.activeCount > 0 })

        #expect(log.activeCount > 0)
    }

    @Test func noTransitionWhenTheSameImageIsDisplayedAgain() async {
        let log = TransitionLog()
        let completions = Ref(0)

        let host = ViewHost(0) { attempt in
            LazyImage(url: Test.url)
                .pipeline(pipeline)
                .reload(id: attempt)
                .imageTransition(log.transition, animation: transitionAnimation, onMemoryCacheHit: true)
                .onCompletion { _ in completions.value += 1 }
        }
        await host.render(until: { completions.value == 1 })
        await settle(log, in: host)

        await host.update(1, until: { completions.value == 2 })
        await host.render()

        #expect(log.activeCount == 0)
    }

    /// Waits for a transition to run out, so that what it does next can't be
    /// mistaken for a new one.
    private func settle(_ log: TransitionLog, in host: ViewHost<some Any, some View>) async {
        await host.render(until: { log.activeCount > 0 })
        var count = -1
        while count != log.activeCount {
            count = log.activeCount
            await host.render()
        }
        log.activeCount = 0
    }

    @Test func imageIdentityChangesWithANewImage() {
        let identity = DisplayedImageIdentity()
        #expect(identity.update(with: nil) == 0)

        let first = identity.update(with: ImageContainer(image: Test.image))
        #expect(first != 0)

        let second = identity.update(with: ImageContainer(image: PlatformImage()))
        #expect(second != first)

        #expect(identity.update(with: nil) == 0)
        #expect(identity.update(with: ImageContainer(image: PlatformImage())) != second)
    }

    @Test func imageIdentityStaysForTheSameImage() {
        let identity = DisplayedImageIdentity()
        let image = Test.image

        let first = identity.update(with: ImageContainer(image: image))

        #expect(identity.update(with: ImageContainer(image: image)) == first)
    }

    /// A progressive load displays an image many times, and it's one image.
    @Test func imageIdentityStaysFromAPreviewToTheFinalImage() {
        let identity = DisplayedImageIdentity()

        let first = identity.update(with: ImageContainer(image: PlatformImage(), isPreview: true))

        #expect(identity.update(with: ImageContainer(image: PlatformImage(), isPreview: true)) == first)
        #expect(identity.update(with: ImageContainer(image: PlatformImage())) == first)
    }

    // MARK: - Modifiers That Change the Content

    /// `failureView(_:)` and `imageTransition(_:animation:onMemoryCacheHit:)`
    /// make a view of a different type out of the one they're called on, which
    /// has to bring along everything that was set on it.
    @Test func optionsSetBeforeTheModifiersAreKept() async throws {
        let tasks = Ref<[ImageTask]>([])
        let completed = TestExpectation()
        dataLoader.isSuspended = true

        let host = ViewHost(0) { attempt in
            LazyImage(url: Test.url) { (state: LazyImageState) in
                state.image
            }
            .processors([MockImageProcessor(id: "1")])
            .priority(.high)
            .pipeline(pipeline)
            .onDisappear(.lowerPriority)
            .reload(id: attempt)
            .onStart { tasks.value.append($0) }
            .onCompletion { _ in completed.fulfill() }
            .failureView { _ in SwiftUI.Color.green }
            .imageTransition(.opacity)
        }
        await host.render(until: { !tasks.value.isEmpty })

        let task = try #require(tasks.value.first)
        #expect(task.request.priority == .high)
        #expect(task.request.processors.count == 1)

        await host.hideContent(until: { task.priority == .veryLow })
        #expect(!task.isCancelled)
        await host.showContent(until: { task.priority == .high })

        dataLoader.isSuspended = false
        await completed.wait()

        imageCache.removeAll()
        await host.update(1, until: { tasks.value.count == 2 })
    }

    @Test func modifiersWorkOnTheResultOfTheOnesThatChangeTheContent() async {
        dataLoader.results[Test.url] = failure
        let errors = Ref(0)
        let starts = Ref(0)

        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .imageTransition(.opacity)
                .failureView { _ in
                    let _ = errors.value += 1
                    SwiftUI.Color.green
                }
                .pipeline(pipeline)
                .onStart { _ in starts.value += 1 }
        }
        await host.render(until: { errors.value > 0 })

        #expect(starts.value == 1)
        withExtendedLifetime(host) {}
    }
}

/// Records a transition running. The body of a transition's modifier gets built
/// with no animation too, so what shows that it ran is the modifier receiving a
/// value between its two ends.
@MainActor
private final class TransitionLog {
    var activeCount = 0

    var transition: AnyTransition {
        .modifier(active: Recorder(log: self, progress: 0), identity: Recorder(log: self, progress: 1))
    }

    private struct Recorder: ViewModifier, @preconcurrency Animatable {
        let log: TransitionLog
        var progress: Double

        var animatableData: Double {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            if progress > 0, progress < 1 {
                MainActor.assumeIsolated { log.activeCount += 1 }
            }
            return content.opacity(progress)
        }
    }
}

#endif
