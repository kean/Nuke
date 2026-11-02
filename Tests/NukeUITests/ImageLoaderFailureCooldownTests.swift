// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

/// A user who taps Retry has to reach the server, whatever the pipeline
/// remembers about the URL.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct ImageLoaderFailureCooldownTests {
    private let dataLoader = MockDataLoader()
    private let loader = ImageLoader()

    init() {
        let dataLoader = dataLoader
        loader.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.failureCooldown = .init(duration: 3600)
        }
        dataLoader.results[Test.url] = .failure(DataLoader.Error.statusCodeUnacceptable(404) as NSError)
    }

    @Test func loadingTheRequestAgainDoesNotReachTheServer() async {
        // Given
        _ = await loader.load(Test.request).result

        // When
        let result = await loader.load(Test.request).result

        // Then
        guard case .failure(.urlInCooldown) = result else {
            Issue.record("Unexpected result: \(result)")
            return
        }
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func reloadReachesTheServer() async throws {
        // Given
        _ = await loader.load(Test.request).result

        // When the image is back
        dataLoader.results[Test.url] = nil
        let handle = try #require(loader.reload())
        _ = try await handle.response

        // Then
        #expect(dataLoader.createdTaskCount == 2)
        #expect(loader.state.image != nil)
    }

    @Test func reloadLeavesTheRequestInTheStateAlone() async throws {
        // Given
        _ = await loader.load(Test.request).result

        // When
        dataLoader.isSuspended = true
        let handle = try #require(loader.reload())

        // Then only the task has the option
        #expect(loader.state.request?.options == [])
        #expect(handle.task?.request.options == .skipFailureCooldown)
    }

    @Test func loadingTheSameRequestKeepsTheRunningReload() async throws {
        // Given
        _ = await loader.load(Test.request).result
        dataLoader.isSuspended = true
        let reload = try #require(loader.reload())

        // When
        let load = loader.load(Test.request)

        // Then
        #expect(load.task === reload.task)
        #expect(reload.task?.isCancelled == false)
    }

    @Test func reloadOfAPipelineWithoutACooldownLeavesTheOptionsAlone() async throws {
        // Given
        loader.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        _ = await loader.load(Test.request).result

        // When
        dataLoader.isSuspended = true
        let handle = try #require(loader.reload())

        // Then it can still join a load of the same request by another view
        #expect(handle.task?.request.options == [])
    }
}
