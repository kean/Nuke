// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineConfigurationTests {

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

    @Test func withDataCacheAppliesTheSizeLimit() throws {
        // When
        let configuration = ImagePipeline.Configuration.withDataCache(
            name: "com.github.kean.Nuke.Tests.\(UUID().uuidString)",
            sizeLimit: 1234
        )

        // Then
        let dataCache = try #require(configuration.dataCache as? DataCache)
        defer { try? FileManager.default.removeItem(at: dataCache.path) }
        #expect(dataCache.sizeLimit == 1234)
        // ...and the HTTP cache is disabled in favor of the aggressive one
        #expect((configuration.dataLoader as? DataLoader)?.session.configuration.urlCache == nil)
    }

    @Test func withDataCacheDefaultsToTheStandardSizeLimit() throws {
        // When
        let configuration = ImagePipeline.Configuration.withDataCache(
            name: "com.github.kean.Nuke.Tests.\(UUID().uuidString)"
        )

        // Then
        let dataCache = try #require(configuration.dataCache as? DataCache)
        defer { try? FileManager.default.removeItem(at: dataCache.path) }
        #expect(dataCache.sizeLimit == 1024 * 1024 * 150)
    }

    // MARK: URLCache

    @Test func withURLCache() {
        // When
        let configuration = ImagePipeline.Configuration.withURLCache

        // Then the aggressive disk cache is disabled in favor of the HTTP one
        #expect(configuration.dataCache == nil)
        #expect((configuration.dataLoader as? DataLoader)?.session.configuration.urlCache != nil)
    }

    // MARK: - Default Values

    @Test func isTaskCoalescingEnabledByDefault() {
        let config = ImagePipeline.Configuration()
        #expect(config.isTaskCoalescingEnabled == true)
    }

    @Test func isRateLimiterEnabledByDefault() {
        let config = ImagePipeline.Configuration()
        #expect(config.isRateLimiterEnabled == true)
    }

    @Test func isProgressiveDecodingDisabledByDefault() {
        let config = ImagePipeline.Configuration()
        #expect(config.isProgressiveDecodingEnabled == false)
    }

    @Test func dataCachePolicyDefaultsToStoreOriginalData() {
        let config = ImagePipeline.Configuration()
        #expect(config.dataCachePolicy == .storeOriginalData)
    }

    @Test func isDecompressionEnabledByDefaultExceptOnMacOS() {
        let config = ImagePipeline.Configuration()
#if os(macOS)
        #expect(config.isDecompressionEnabled == false)
#else
        #expect(config.isDecompressionEnabled == true)
#endif
    }

    @Test func isDecompressionEnabledCanBeChanged() {
        // Given
        var config = ImagePipeline.Configuration()
        let original = config.isDecompressionEnabled

        // When
        config.isDecompressionEnabled = !original

        // Then
        #expect(config.isDecompressionEnabled == !original)
    }

    @Test func isUsingPrepareForDisplayIsEnabledByDefault() {
        let config = ImagePipeline.Configuration()
        #expect(config.isUsingPrepareForDisplay == true)
    }

    @Test func isLocalResourcesSupportEnabledByDefault() {
        let config = ImagePipeline.Configuration()
        #expect(config.isLocalResourcesSupportEnabled == true)
    }

    // MARK: - Incremental Delivery

    /// Copies of a configuration share the data loader: a pipeline derived
    /// from a progressive one must not take the increments away from it.
    @Test func derivedPipelineKeepsIncrementalDeliveryOfTheSharedDataLoader() {
        // GIVEN a progressive pipeline
        let dataLoader = DataLoader()
        let progressive = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
        }

        // WHEN another pipeline is derived from its configuration
        var configuration = progressive.configuration
        configuration.isProgressiveDecodingEnabled = false
        _ = ImagePipeline(configuration: configuration)

        // THEN the first pipeline still gets partial response bodies
        #expect(progressive.configuration.isProgressiveDecodingEnabled == true)
        #expect(dataLoader.prefersIncrementalDelivery == true)
    }

    @Test func pipelineKeepsIncrementalDeliveryConfiguredOnTheDataLoader() {
        let dataLoader = DataLoader()
        dataLoader.prefersIncrementalDelivery = true
        _ = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = false
        }
        #expect(dataLoader.prefersIncrementalDelivery == true)
    }
}
