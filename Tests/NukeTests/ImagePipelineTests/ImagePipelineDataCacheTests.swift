// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDataCachingTests {
    let dataLoader: MockDataLoader
    let dataCache: MockDataCache
    let pipeline: ImagePipeline

    init() {
        let dataCache = MockDataCache()
        let dataLoader = MockDataLoader()
        self.dataCache = dataCache
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
    }

    // MARK: - Basics

    @Test func imageIsLoaded() async throws {
        // Given
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString] = Test.data

        // When/Then
        _ = try await pipeline.image(for: Test.request)
    }

    @Test func dataIsStoredInCache() async throws {
        // When
        _ = try await pipeline.image(for: Test.request)

        // Then
        #expect(!dataCache.store.isEmpty)
    }

    @Test func thumbnailOptionsDataCacheStoresOriginalDataByDefault() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
            $0.imageCache = MockImageCache()
        }

        // WHEN
        var request = ImageRequest(url: Test.url)
        request.thumbnail = .init(
            size: CGSize(width: 400, height: 400),
            unit: .pixels,
            contentMode: .aspectFit
        )

        _ = try await pipeline.image(for: request)

        // THEN
        do { // Check memory cache
            // Image does not exists for the original image
            #expect(pipeline.cache.cachedImage(for: ImageRequest(url: Test.url), caches: [.memory]) == nil)

            // Image exists for thumbnail
            let thumbnail = try #require(pipeline.cache.cachedImage(for: request, caches: [.memory]))
            #expect(thumbnail.image.sizeInPixels == CGSize(width: 400, height: 300))
        }

        do { // Check disk cache
            // Data exists for the original image
            let original = try #require(pipeline.cache.cachedImage(for: ImageRequest(url: Test.url), caches: [.disk]))
            #expect(original.image.sizeInPixels == CGSize(width: 640, height: 480))

            // Data does not exist for thumbnail
            #expect(pipeline.cache.cachedData(for: request) == nil)
        }
    }

    @Test func thumbnailOptionsDataCacheStoresOriginalDataWithStoreAllPolicy() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
            $0.imageCache = MockImageCache()
        }

        // WHEN
        var request = ImageRequest(url: Test.url)
        request.thumbnail = .init(
            size: CGSize(width: 400, height: 400),
            unit: .pixels,
            contentMode: .aspectFit
        )

        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        do { // Check memory cache
            // Image does not exists for the original image
            #expect(pipeline.cache.cachedImage(for: ImageRequest(url: Test.url), caches: [.memory]) == nil)

            // Image exists for thumbnail
            let thumbnail = try #require(pipeline.cache.cachedImage(for: request, caches: [.memory]))
            #expect(thumbnail.image.sizeInPixels == CGSize(width: 400, height: 300))
        }

        do { // Check disk cache
            // Data exists for the original image
            let original = try #require(pipeline.cache.cachedImage(for: ImageRequest(url: Test.url), caches: [.disk]))
            #expect(original.image.sizeInPixels == CGSize(width: 640, height: 480))

            // Data exists for thumbnail
            let thumbnail = try #require(pipeline.cache.cachedImage(for: request, caches: [.disk]))
            #expect(thumbnail.image.sizeInPixels == CGSize(width: 400, height: 300))
        }
    }

    // MARK: - Updating Priority

    @Test func priorityUpdated() async throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = Test.request
        #expect(request.priority == .normal)

        var task: ImageTask!
        let operations = await queue.waitForOperations(count: 1) {
            task = pipeline.imageTask(with: request)
        }

        // When/Then
        let operation = try #require(operations.first)
        await waitForPriorityChange(of: operation, to: .high) {
            task.priority = .high
        }
    }

    // MARK: - Cancellation

    @Test func operationCancelled() async throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        var task: ImageTask!
        let operations = await queue.waitForOperations(count: 1) {
            task = pipeline.imageTask(with: Test.request)
        }

        // When/Then
        let operation = try #require(operations.first)
        await waitForCancellation(of: operation) {
            task.cancel()
        }
    }

    // MARK: ImageRequest.CachePolicy

    @Test func loadFromCacheOnlyDataCache() async throws {
        // Given
        dataCache.store[Test.url.absoluteString] = Test.data

        var request = Test.request
        request.options = [.returnCacheDataDontLoad]

        // When
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func loadFromCacheOnlyMemoryCache() async throws {
        // Given
        let imageCache = MockImageCache()
        imageCache[Test.request] = ImageContainer(image: Test.image)
        let pipeline = pipeline.reconfigured {
            $0.imageCache = imageCache
        }

        var request = Test.request
        request.options = [.returnCacheDataDontLoad]

        // When
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func loadImageFromCacheOnlyFailsIfNoCache() async {
        // GIVEN no cached data and download disabled
        var request = Test.request
        request.options = [.returnCacheDataDontLoad]

        // WHEN/THEN
        await #expect {
            _ = try await pipeline.image(for: request)
        } throws: {
            ($0 as? ImagePipeline.Error) == .dataMissingInCache
        }
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func loadDataFromCacheOnlyFailsIfNoCache() async {
        // GIVEN no cached data and download disabled
        var request = Test.request
        request.options = [.returnCacheDataDontLoad]

        // WHEN/THEN
        await #expect {
            try await pipeline.data(for: request)
        } throws: {
            ($0 as? ImagePipeline.Error) == .dataMissingInCache
        }
        #expect(dataLoader.createdTaskCount == 0)
    }
}

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDataCachePolicyTests {
    let dataLoader: MockDataLoader
    let dataCache: MockDataCache
    let pipeline: ImagePipeline
    let encoder: MockImageEncoder
    let processorFactory: MockProcessorFactory
    let request: ImageRequest

    init() {
        let dataCache = MockDataCache()
        let dataLoader = MockDataLoader()
        let encoder = MockImageEncoder(result: Test.data(name: "fixture-tiny", extension: "jpeg"))
        let processorFactory = MockProcessorFactory()
        self.dataCache = dataCache
        self.dataLoader = dataLoader
        self.encoder = encoder
        self.processorFactory = processorFactory
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.makeImageEncoder = { _ in encoder }
        }
        self.request = ImageRequest(url: Test.url, processors: [processorFactory.make(id: "1")])
    }

    // MARK: - Basics

    @Test func processedImageLoadedFromDataCache() async throws {
        // Given processed image data stored in data cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When/Then
        _ = try await pipeline.image(for: request)

        // Then
        #expect(processorFactory.numberOfProcessorsApplied == 0)
    }

#if !os(macOS)
    @Test func processedImageIsDecompressed() async throws {
        // Given processed image data stored in data cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When/Then
        let response = try await pipeline.imageTask(with: request).response
        let image = response.image
        #expect(ImageDecompression.isDecompressionNeeded(for: image) == nil)
    }

    @Test func processedImageIsStoredInMemoryCache() async throws {
        // Given processed image data stored in data cache
        let cache = MockImageCache()
        let pipeline = pipeline.reconfigured {
            $0.imageCache = cache
        }
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When
        _ = try await pipeline.image(for: request)

        // Then decompressed image is stored in disk cache
        let container = cache[request]
        #expect(container != nil)

        let image = try #require(container?.image)
        #expect(ImageDecompression.isDecompressionNeeded(for: image) == nil)
    }

    @Test func processedImageNotDecompressedWhenDecompressionDisabled() async throws {
        // Given pipeline with decompression disabled
        let pipeline = pipeline.reconfigured {
            $0.isDecompressionEnabled = false
        }

        // Given processed image data stored in data cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When/Then
        let response = try await pipeline.imageTask(with: request).response
        let image = response.image
        let isDecompressionNeeded = ImageDecompression.isDecompressionNeeded(for: image)
        #expect(isDecompressionNeeded == true)
    }
#endif

    // MARK: DataCachePolicy

    /// What each policy stores for image tasks. A data task has no image to
    /// encode, so the rows that encode one differ from the data task table in
    /// `ImagePipelineLoadDataTests`.
    @Test(arguments: [
        PolicyCase(.automatic, .processed, encodeCount: 1, stored: [.processed]),
        PolicyCase(.automatic, .original, encodeCount: 0, stored: [.original]),
        PolicyCase(.automatic, .processedThenOriginal, encodeCount: 1, stored: [.processed, .original]),
        PolicyCase(.storeEncodedImages, .processed, encodeCount: 1, stored: [.processed]),
        PolicyCase(.storeEncodedImages, .original, encodeCount: 1, stored: [.original]),
        PolicyCase(.storeEncodedImages, .processedThenOriginal, encodeCount: 2, stored: [.processed, .original]),
        PolicyCase(.storeOriginalData, .processed, encodeCount: 0, stored: [.original]),
        PolicyCase(.storeOriginalData, .original, encodeCount: 0, stored: [.original]),
        PolicyCase(.storeOriginalData, .processedAndOriginalCoalesced, encodeCount: 0, stored: [.original]),
        PolicyCase(.storeAll, .processed, encodeCount: 1, stored: [.processed, .original]),
        PolicyCase(.storeAll, .original, encodeCount: 0, stored: [.original]),
        PolicyCase(.storeAll, .processedThenOriginal, encodeCount: 1, stored: [.processed, .original])
    ])
    func policyDecidesWhatImageTasksStore(_ policyCase: PolicyCase) async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = policyCase.policy
        }

        // WHEN
        let requests = policyCase.requests.imageRequests
        if policyCase.requests == .processedAndOriginalCoalesced {
            let tasks = await withSuspendedDataLoading(for: pipeline, expectedCount: requests.count) {
                requests.map { pipeline.imageTask(with: $0) }
            }
            for task in tasks {
                _ = try await task.response
            }
        } else {
            for request in requests {
                _ = try await pipeline.image(for: request)
            }
        }
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(encoder.encodeCount == policyCase.encodeCount)
        #expect(Set(dataCache.store.keys) == Set(policyCase.stored.map(\.key)))
        #expect(dataCache.writeCount == policyCase.stored.count)
    }

    /// The requests for `Test.url` that a row loads with a data cache policy,
    /// and what the policy stores for them.
    struct PolicyCase: Sendable, CustomStringConvertible {
        let policy: ImagePipeline.DataCachePolicy
        let requests: Requests
        let encodeCount: Int
        let stored: Set<Entry>

        init(_ policy: ImagePipeline.DataCachePolicy, _ requests: Requests, encodeCount: Int, stored: Set<Entry>) {
            self.policy = policy
            self.requests = requests
            self.encodeCount = encodeCount
            self.stored = stored
        }

        var description: String {
            "\(policy), \(requests.rawValue)"
        }

        /// Loaded one after the other, or at the same time when coalesced.
        enum Requests: String, Sendable {
            case processed
            case original
            case processedThenOriginal = "processed then original"
            case processedAndOriginalCoalesced = "processed and original, coalesced"

            var imageRequests: [ImageRequest] {
                let processed = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
                let original = ImageRequest(url: Test.url)
                switch self {
                case .processed: return [processed]
                case .original: return [original]
                case .processedThenOriginal, .processedAndOriginalCoalesced: return [processed, original]
                }
            }
        }

        /// A disk cache entry.
        enum Entry: Sendable {
            /// The entry of the request without processors: the original
            /// data, or its encoded image with `.storeEncodedImages`.
            case original
            /// The entry of the processed request: its encoded image.
            case processed

            var key: String {
                switch self {
                case .original: return Test.url.absoluteString
                case .processed: return Test.url.absoluteString + "p1"
                }
            }
        }
    }

    @Test func policyAutomaticGivenOriginalImageInMemoryCache() async throws {
        // GIVEN
        let imageCache = MockImageCache()
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
            $0.imageCache = imageCache
        }
        imageCache[ImageRequest(url: Test.url)] = Test.container

        // WHEN
        _ = try await pipeline.image(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        // encoded processed image is stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
        #expect(dataLoader.createdTaskCount == 0)
    }

    // MARK: ImageRequest.Options.disableDiskCacheWrites

    @Test(arguments: [ImagePipeline.DataCachePolicy.automatic, .storeAll, .storeEncodedImages])
    func encodedImageNotStoredWhenDiskCacheWritesDisabled(policy: ImagePipeline.DataCachePolicy) async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = policy
        }

        // GIVEN request with a processor that disables disk cache writes
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")], options: [.disableDiskCacheWrites])

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN nothing is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.isEmpty)
    }

    // MARK: Coalesced Requests

    @Test(arguments: [ImagePipeline.DataCachePolicy.automatic, .storeOriginalData], CoalescedRequest.mixes)
    func policyGivenCoalescedRequests(policy: ImagePipeline.DataCachePolicy, requests: [CoalescedRequest]) async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = policy
        }

        // WHEN the requests wait for the same download
        let loads = await withSuspendedDataLoading(for: pipeline, expectedCount: requests.count) {
            requests.map { request in
                Task {
                    if request.isDataTask {
                        _ = try await pipeline.data(for: request.imageRequest)
                    } else {
                        _ = try await pipeline.image(for: request.imageRequest)
                    }
                }
            }
        }
        for load in loads {
            try await load.value
        }
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN the original data is stored if any of the requests allows disk
        // cache writes and, with `.automatic`, any of them has no processors –
        // not necessarily the same one
        let isStored = requests.contains { !$0.disablesDiskCacheWrites } &&
            (policy == .storeOriginalData || requests.contains { !$0.hasProcessor })
        #expect(dataLoader.createdTaskCount == 1)
        #expect(dataCache.containsData(for: Test.url.absoluteString) == isStored)
    }

    /// A request that waits for the same download as the others in its test case.
    struct CoalescedRequest: Sendable, CustomStringConvertible {
        var isDataTask = false
        var hasProcessor = false
        var disablesDiskCacheWrites = false

        var imageRequest: ImageRequest {
            ImageRequest(
                url: Test.url,
                processors: hasProcessor ? [MockImageProcessor(id: "p1")] : [],
                options: disablesDiskCacheWrites ? [.disableDiskCacheWrites] : []
            )
        }

        var description: String {
            [isDataTask ? "data" : "image", hasProcessor ? "p1" : nil, disablesDiskCacheWrites ? "disableDiskCacheWrites" : nil]
                .compactMap { $0 }
                .joined(separator: " ")
        }

        /// Every kind of request on its own, and every pair of them.
        static var mixes: [[CoalescedRequest]] {
            let kinds = [
                CoalescedRequest(),
                CoalescedRequest(disablesDiskCacheWrites: true),
                CoalescedRequest(hasProcessor: true),
                CoalescedRequest(hasProcessor: true, disablesDiskCacheWrites: true),
                CoalescedRequest(isDataTask: true),
                CoalescedRequest(isDataTask: true, disablesDiskCacheWrites: true)
            ]
            return kinds.indices.flatMap { i in
                [[kinds[i]]] + kinds[i...].map { [kinds[i], $0] }
            }
        }
    }

    // MARK: Local Resources

    @Test func imagesFromLocalStorageNotCached() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url(forResource: "fixture", extension: "jpeg"))

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN nothing is stored in disk cache: the original is already local
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    @Test func processedImagesFromLocalStorageAreCached() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url(forResource: "fixture", extension: "jpeg"), processors: [.resize(width: 100)])

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN processed image is stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func imagesFromData() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request without a processor
        let data = Test.data(name: "fixture", extension: "jpeg")
        let url = URL(string: "data:image/jpeg;base64,\(data.base64EncodedString())")
        let request = ImageRequest(url: url)

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN nothing is stored in disk cache: the data is in the URL
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    // MARK: Misc

    @Test func setCustomImageEncoder() async throws {
        // Given
        let encoder = MockImageEncoder(result: nil)

        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
            $0.makeImageEncoder = { _ in
                return encoder
            }
        }

        // When
        _ = try await pipeline.image(for: request)

        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "1") == nil)
    }

    // MARK: Integration with Thumbnail Feature

    @Test func originalDataStoredWhenThumbnailRequested() async throws {
        // GIVEN
        var request = ImageRequest(url: Test.url)
        request.thumbnail = .init(maxPixelSize: 400)

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN
        #expect(dataCache.containsData(for: "http://test.com/example.jpeg"))
    }

    // MARK: - Thumbnail + Original Data Reuse

    @Test func thumbnailRequestReusesOriginalDataFromDiskCache() async throws {
        // GIVEN original image is loaded (no thumbnail), caching original data to disk
        _ = try await pipeline.image(for: Test.request)
        #expect(dataCache.containsData(for: Test.url.absoluteString))

        // WHEN a thumbnail of the same URL is requested
        var thumbnailRequest = ImageRequest(url: Test.url)
        thumbnailRequest.thumbnail = .init(maxPixelSize: 400)

        _ = try await pipeline.image(for: thumbnailRequest)

        // THEN no additional network request is made — the original data from
        // the disk cache should be reused to generate the thumbnail locally
        #expect(dataLoader.createdTaskCount == 1)
    }
}
