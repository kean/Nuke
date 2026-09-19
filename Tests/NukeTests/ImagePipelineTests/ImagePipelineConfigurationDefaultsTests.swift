// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineConfigurationDefaultsTests {
    @Test func optionDefaults() {
        // When
        let configuration = ImagePipeline.Configuration()

        // Then
        #expect(configuration.dataLoader is DataLoader)
        #expect(configuration.dataCache == nil)
        #expect(configuration.progressiveDecodingInterval == 0.5)
        #expect(configuration.isStoringPreviewsInMemoryCache == true)
        #expect(configuration.isAnimatedImageParsingEnabled == true)
        #expect(configuration.isResumableDataEnabled == true)
        #expect(configuration.isDiagnosticsEnabled == ImagePipeline.Diagnostics.isEnabledByEnvironment)
    }

    /// "10% of physical memory, capped at 200 MB."
    @Test func maximumResponseDataSizeDefault() throws {
        // When
        let limit = try #require(ImagePipeline.Configuration().maximumResponseDataSize)

        // Then
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        #expect(limit == Int(min(200 * 1024 * 1024, physicalMemory / 10)))
        #expect(limit > 0)
    }

    @Test func taskQueueDefaults() {
        // When
        let configuration = ImagePipeline.Configuration()

        // Then
        #expect(configuration.dataLoadingQueue.maxConcurrentTaskCount == 6)
        #expect(configuration.imageDecodingQueue.maxConcurrentTaskCount == 2)
        #expect(configuration.imageEncodingQueue.maxConcurrentTaskCount == 1)
        #expect(configuration.imageProcessingQueue.maxConcurrentTaskCount == 2)
        #expect(configuration.imageDecompressingQueue.maxConcurrentTaskCount == 2)
        #expect(configuration.dataLoadingQueue.isSuspended == false)
    }

    // MARK: - Image Cache

    @Test func defaultImageCacheIsShared() {
        let configuration = ImagePipeline.Configuration()
        #expect((configuration.imageCache as? ImageCache) === ImageCache.shared)
    }

    /// Setting `nil` disables the memory cache; it must not fall back to the
    /// shared one.
    @Test func imageCacheSetToNilStaysNil() {
        // When
        var configuration = ImagePipeline.Configuration()
        configuration.imageCache = nil

        // Then
        #expect(configuration.imageCache == nil)
        let copy = configuration
        #expect(copy.imageCache == nil)
        #expect(ImagePipeline(configuration: configuration).configuration.imageCache == nil)
    }

    @Test func customImageCacheIsReturned() {
        // When
        let cache = MockImageCache()
        var configuration = ImagePipeline.Configuration()
        configuration.imageCache = cache

        // Then
        #expect((configuration.imageCache as? MockImageCache) === cache)

        // When
        configuration.imageCache = nil

        // Then
        #expect(configuration.imageCache == nil)
    }

    // MARK: - Codecs

    @Test func defaultDecoderAndEncoder() {
        // Given
        let configuration = ImagePipeline.Configuration()
        let request = Test.request

        // When
        let decoder = configuration.makeImageDecoder(ImageDecodingContext(request: request, data: Test.data))
        let encoder = configuration.makeImageEncoder(ImageEncodingContext(request: request, image: Test.image, urlResponse: nil))

        // Then
        #expect(decoder is ImageDecoders.Default)
        #expect(encoder is ImageEncoders.Default)
    }

    // MARK: - Predefined Configurations

    @Test func withURLCacheUsesSharedHTTPCache() throws {
        // When
        let configuration = ImagePipeline.Configuration.withURLCache

        // Then
        let urlCache = try #require((configuration.dataLoader as? DataLoader)?.session.configuration.urlCache)
        #expect(urlCache === DataLoader.sharedUrlCache)
        #expect((configuration.imageCache as? ImageCache) === ImageCache.shared)
    }

    @Test func withDataCacheUsesTheGivenName() throws {
        // Given
        let name = "com.github.kean.Nuke.Tests.\(UUID().uuidString)"

        // When
        let configuration = ImagePipeline.Configuration.withDataCache(name: name)

        // Then
        let dataCache = try #require(configuration.dataCache as? DataCache)
        defer { try? FileManager.default.removeItem(at: dataCache.path) }
        #expect(dataCache.path.lastPathComponent == name)
        #expect((configuration.imageCache as? ImageCache) === ImageCache.shared)
        #expect(configuration.dataCachePolicy == .storeOriginalData)
    }
}

/// `Configuration` is a struct, but the task queues and the dependencies are
/// classes: the copies share them.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineConfigurationSharingTests {
    /// The documented caveat: changing a queue on a copy changes it for the
    /// configuration it came from.
    @Test func copiesShareTaskQueues() {
        // Given
        let configuration = ImagePipeline.Configuration(dataLoader: MockDataLoader())

        // When
        let copy = configuration
        copy.imageProcessingQueue.maxConcurrentTaskCount = 1

        // Then
        #expect(configuration.imageProcessingQueue.maxConcurrentTaskCount == 1)
        #expect(copy.dataLoadingQueue === configuration.dataLoadingQueue)
        #expect(copy.imageDecodingQueue === configuration.imageDecodingQueue)
        #expect(copy.imageEncodingQueue === configuration.imageEncodingQueue)
        #expect(copy.imageDecompressingQueue === configuration.imageDecompressingQueue)
    }

    @Test func pipelineSharesQueuesOfItsConfiguration() {
        // Given
        let pipeline = ImagePipeline { $0.dataLoader = MockDataLoader() }

        // When
        let configuration = pipeline.configuration
        configuration.dataLoadingQueue.maxConcurrentTaskCount = 1

        // Then
        #expect(pipeline.configuration.dataLoadingQueue.maxConcurrentTaskCount == 1)
    }

    /// "Start from a fresh configuration – `Configuration()` or one of the
    /// predefined configurations – each of which creates its own queues."
    @Test func freshConfigurationsHaveTheirOwnQueues() throws {
        // Given
        let dataCacheName = "com.github.kean.Nuke.Tests.\(UUID().uuidString)"
        let configurations = [
            ImagePipeline.Configuration(dataLoader: MockDataLoader()),
            ImagePipeline.Configuration(dataLoader: MockDataLoader()),
            ImagePipeline.Configuration.withURLCache,
            ImagePipeline.Configuration.withDataCache(name: dataCacheName)
        ]
        defer {
            if let dataCache = configurations.last?.dataCache as? DataCache {
                try? FileManager.default.removeItem(at: dataCache.path)
            }
        }

        // Then
        let queues: [KeyPath<ImagePipeline.Configuration, TaskQueue>] = [
            \.dataLoadingQueue, \.imageDecodingQueue, \.imageEncodingQueue, \.imageProcessingQueue, \.imageDecompressingQueue
        ]
        for queue in queues {
            let instances = configurations.map { ObjectIdentifier($0[keyPath: queue]) }
            #expect(Set(instances).count == configurations.count)
        }
    }

    /// Unlike the queues, the plain options have value semantics: changing the
    /// struct the pipeline was created with has no effect on the pipeline.
    @Test func plainOptionsAreNotSharedWithPipeline() {
        // Given
        var configuration = ImagePipeline.Configuration(dataLoader: MockDataLoader())
        let pipeline = ImagePipeline(configuration: configuration)

        // When
        configuration.isTaskCoalescingEnabled = false
        configuration.dataCachePolicy = .storeAll
        configuration.isDecompressionEnabled.toggle()
        configuration.maximumResponseDataSize = 1

        // Then
        #expect(pipeline.configuration.isTaskCoalescingEnabled == true)
        #expect(pipeline.configuration.dataCachePolicy == .storeOriginalData)
        #expect(pipeline.configuration.isDecompressionEnabled == ImagePipeline.Configuration().isDecompressionEnabled)
        #expect(pipeline.configuration.maximumResponseDataSize != 1)
    }

    @Test @ImagePipelineActor func rateLimiterIsCreatedOnlyWhenEnabled() {
        let enabled = ImagePipeline { $0.dataLoader = MockDataLoader() }
        let disabled = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.isRateLimiterEnabled = false
        }
        #expect(enabled.rateLimiter != nil)
        #expect(disabled.rateLimiter == nil)
    }

    @Test func diagnosticsRecorderIsCreatedOnlyWhenEnabled() {
        let enabled = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.isDiagnosticsEnabled = true
        }
        let disabled = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.isDiagnosticsEnabled = false
        }
        #expect(enabled.recorder != nil)
        #expect(disabled.recorder == nil)
    }
}

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineConfigurationBehaviorTests {
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Maximum Response Data Size

    /// The limit is the largest size allowed, not the smallest one rejected.
    @Test func responseOfExactlyMaximumSizeIsAccepted() async throws {
        // Given
        serveTestDataWithExactLength()
        let pipeline = pipeline.reconfigured { $0.maximumResponseDataSize = Test.data.count }

        // When/Then
        _ = try await pipeline.image(for: Test.request)
    }

    @Test func responseOneByteOverMaximumSizeIsRejected() async throws {
        // Given
        serveTestDataWithExactLength()
        let pipeline = pipeline.reconfigured { $0.maximumResponseDataSize = Test.data.count - 1 }

        // When/Then
        await #expect(throws: ImagePipeline.Error.dataDownloadExceededMaximumSize) {
            try await pipeline.image(for: Test.request)
        }
    }

    @Test func nilMaximumSizeDisablesTheCheck() async throws {
        // Given a server that reports twice the length of the data it sends
        let response = URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: Test.data.count * 2, textEncodingName: nil)
        dataLoader.results[Test.url] = .success((Test.data, response))

        // Then a limit rejects it upfront, going by the reported length
        let limited = pipeline.reconfigured { $0.maximumResponseDataSize = Test.data.count }
        await #expect(throws: ImagePipeline.Error.dataDownloadExceededMaximumSize) {
            try await limited.image(for: Test.request)
        }

        // Then no limit accepts it
        let unlimited = pipeline.reconfigured { $0.maximumResponseDataSize = nil }
        _ = try await unlimited.image(for: Test.request)
    }

    private func serveTestDataWithExactLength() {
        let response = URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: Test.data.count, textEncodingName: nil)
        dataLoader.results[Test.url] = .success((Test.data, response))
    }
}
