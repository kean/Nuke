// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import SwiftUI
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

/// The pipeline in the environment: `imagePipeline(_:)`, and how `LazyImage`
/// resolves it against its own `pipeline(_:)`.
@Suite(.serialized, .timeLimit(.minutes(5))) @MainActor
struct LazyImageEnvironmentPipelineTests {
    let dataLoader = MockDataLoader()
    let pipeline: ImagePipeline

    init() {
        let dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    private func makePipeline() -> (ImagePipeline, MockDataLoader) {
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        return (pipeline, dataLoader)
    }

    // MARK: - Resolution

    @Test func environmentPipelineIsUsed() async {
        let completed = TestExpectation()
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .onCompletion { _ in completed.fulfill() }
                .imagePipeline(pipeline)
        }
        await completed.wait()

        #expect(dataLoader.createdTaskCount == 1)
        withExtendedLifetime(host) {}
    }

    @Test func environmentPipelineIsInheritedByDescendants() async {
        let completed = TestExpectation()
        let host = ViewHost(Test.url) { url in
            VStack {
                LazyImage(url: url)
                    .onCompletion { _ in completed.fulfill() }
            }
            .imagePipeline(pipeline)
        }
        await completed.wait()

        #expect(dataLoader.createdTaskCount == 1)
        withExtendedLifetime(host) {}
    }

    @Test func pipelineOfTheViewWinsOverTheEnvironment() async {
        let (own, ownDataLoader) = makePipeline()

        let completed = TestExpectation()
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .pipeline(own)
                .onCompletion { _ in completed.fulfill() }
                .imagePipeline(pipeline)
        }
        await completed.wait()

        #expect(ownDataLoader.createdTaskCount == 1)
        #expect(dataLoader.createdTaskCount == 0)
        withExtendedLifetime(host) {}
    }

    @Test func nearestEnvironmentPipelineWins() async {
        let (inner, innerDataLoader) = makePipeline()

        let completed = TestExpectation()
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url)
                .onCompletion { _ in completed.fulfill() }
                .imagePipeline(inner)
                .imagePipeline(pipeline)
        }
        await completed.wait()

        #expect(innerDataLoader.createdTaskCount == 1)
        #expect(dataLoader.createdTaskCount == 0)
        withExtendedLifetime(host) {}
    }

    @Test func contentClosureFormUsesTheEnvironmentPipeline() async {
        let completed = TestExpectation()
        let host = ViewHost(Test.url) { url in
            LazyImage(url: url) { state in
                if let image = state.image { image } else { EmptyView() }
            }
            .onCompletion { _ in completed.fulfill() }
            .imagePipeline(pipeline)
        }
        await completed.wait()

        #expect(dataLoader.createdTaskCount == 1)
        withExtendedLifetime(host) {}
    }

    // MARK: - Changes

    @Test func changingTheEnvironmentPipelineReloads() async {
        let (other, otherDataLoader) = makePipeline()
        let completions = Ref(0)
        let first = TestExpectation()

        let host = ViewHost(pipeline) { pipeline in
            LazyImage(url: Test.url)
                .onCompletion { _ in
                    completions.value += 1
                    if completions.value == 1 { first.fulfill() }
                }
                .imagePipeline(pipeline)
        }
        await first.wait()

        await host.update(other, until: { completions.value == 2 })

        #expect(completions.value == 2)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(otherDataLoader.createdTaskCount == 1)
    }

    @Test func rebuildingTheViewWithTheSameEnvironmentPipelineDoesNotReload() async {
        let completions = Ref(0)
        let first = TestExpectation()

        let host = ViewHost(0) { _ in
            LazyImage(url: Test.url)
                .onCompletion { _ in
                    completions.value += 1
                    first.fulfill()
                }
                .imagePipeline(pipeline)
        }
        await first.wait()

        await host.update(1)

        #expect(completions.value == 1)
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Default

    @Test func environmentDefaultsToTheSharedPipeline() {
        #expect(EnvironmentValues().imagePipeline === ImagePipeline.shared)
    }

    /// The default must not be captured when the environment key is first
    /// read: apps assign `ImagePipeline.shared` at launch, at any time.
    @Test func environmentDefaultFollowsAssignmentsToTheSharedPipeline() {
        let original = ImagePipeline.shared
        defer { ImagePipeline.shared = original }

        _ = EnvironmentValues().imagePipeline
        ImagePipeline.shared = pipeline

        #expect(EnvironmentValues().imagePipeline === pipeline)
    }

    @Test func settingTheEnvironmentValueDirectly() {
        var values = EnvironmentValues()
        values.imagePipeline = pipeline

        #expect(values.imagePipeline === pipeline)
    }
}

#endif
