// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite struct ImagePipelineConfigurationTests {

    @Test func imageIsLoadedWithRateLimiterDisabled() async throws {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isRateLimiterEnabled = false
        }

        // When/Then
        _ = try await pipeline.image(for: Test.request)
    }

    // MARK: DataCache

    @Test func withDataCache() {
        let pipeline = ImagePipeline(configuration: .withDataCache)
        #expect(pipeline.configuration.dataCache != nil)
    }

    @Test func enablingSignposts() {
        ImagePipeline.Configuration.isSignpostLoggingEnabled = false // Just padding
        ImagePipeline.Configuration.isSignpostLoggingEnabled = true
        ImagePipeline.Configuration.isSignpostLoggingEnabled = false
    }
}
