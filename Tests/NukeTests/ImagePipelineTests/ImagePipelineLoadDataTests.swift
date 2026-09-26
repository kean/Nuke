// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineLoadDataTests {
    let dataLoader: MockDataLoader
    let dataCache: MockDataCache
    let pipeline: ImagePipeline
    let encoder: MockImageEncoder

    init() {
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let encoder = MockImageEncoder(result: Test.data)
        self.dataLoader = dataLoader
        self.dataCache = dataCache
        self.encoder = encoder
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.makeImageEncoder = { _ in encoder }
        }
    }

    // MARK: - Errors

    @Test func loadWithInvalidURL() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataLoader = DataLoader()
        }

        // WHEN/THEN
        do {
            _ = try await pipeline.data(for: ImageRequest(url: URL(string: "")))
            Issue.record("Expected failure")
        } catch {
            // Expected
        }
    }

    @Test func downloadExceedingMaximumResponseDataSize() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.maximumResponseDataSize = 1024
        }

        // WHEN/THEN
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Expected failure")
        } catch {
            guard case .dataDownloadExceededMaximumSize = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    /// When the server doesn't report the size upfront, the limit is enforced
    /// against the data received so far.
    @Test func downloadExceedingMaximumResponseDataSizeWithUnknownContentLength() async throws {
        // GIVEN a response with no `expectedContentLength`
        let response = URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: -1, textEncodingName: nil)
        dataLoader.results[Test.url] = .success((Test.data, response))
        let pipeline = pipeline.reconfigured {
            $0.maximumResponseDataSize = 1024
        }

        // WHEN/THEN
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Expected failure")
        } catch {
            guard case .dataDownloadExceededMaximumSize = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    // MARK: - ImageRequest.CachePolicy

    @Test func cacheLookupWithDefaultPolicyImageStored() async throws {
        // GIVEN
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)

        // WHEN
        _ = try await pipeline.data(for: Test.request)

        // THEN
        #expect(dataCache.readCount == 1)
        #expect(dataCache.writeCount == 1) // Initial write
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func cacheLookupWithReloadPolicyImageStored() async throws {
        // GIVEN
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)

        // WHEN
        let request = ImageRequest(url: Test.url, options: [.reloadIgnoringCachedData])
        _ = try await pipeline.data(for: request)

        // THEN
        #expect(dataCache.readCount == 0)
        #expect(dataCache.writeCount == 2) // Initial write + write after fetch
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - Original Data

    @Test func thumbnailRequestIsServedFromTheOriginalDataInDiskCache() async throws {
        // GIVEN
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 100)

        // WHEN the same data is requested twice
        _ = try await pipeline.data(for: request)
        let (data, _) = try await pipeline.data(for: request)

        // THEN the second request reads the original data stored by the first
        #expect(data == Test.data)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func processedRequestIsServedFromTheOriginalDataInDiskCache() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN the same data is requested twice
        _ = try await pipeline.data(for: request)
        let (data, _) = try await pipeline.data(for: request)

        // THEN the second request reads the original data stored by the first
        #expect(data == Test.data)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func thumbnailRequestWithReturnCacheDataDontLoadReadsTheOriginalData() async throws {
        // GIVEN the original data in disk cache
        dataCache.store[Test.url.absoluteString] = Test.data

        // WHEN
        var request = ImageRequest(url: Test.url, options: [.returnCacheDataDontLoad])
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 100)
        let (data, _) = try await pipeline.data(for: request)

        // THEN
        #expect(data == Test.data)
        #expect(dataLoader.createdTaskCount == 0)
    }

    // MARK: - DataCachePolicy

    /// What each policy stores for data tasks: the original data or nothing.
    /// A data task has no image to encode, so the image task table in
    /// `ImagePipelineDataCacheTests` differs in the rows where it encodes one.
    @Test(arguments: [
        PolicyCase(.automatic, .processed, storesOriginalData: false),
        PolicyCase(.automatic, .original, storesOriginalData: true),
        PolicyCase(.automatic, .processedThenOriginal, storesOriginalData: true),
        PolicyCase(.storeEncodedImages, .processed, storesOriginalData: false),
        PolicyCase(.storeEncodedImages, .original, storesOriginalData: false),
        PolicyCase(.storeEncodedImages, .processedThenOriginal, storesOriginalData: false),
        PolicyCase(.storeOriginalData, .processed, storesOriginalData: true),
        PolicyCase(.storeOriginalData, .original, storesOriginalData: true),
        PolicyCase(.storeOriginalData, .processedThenOriginal, storesOriginalData: true),
        PolicyCase(.storeAll, .processed, storesOriginalData: true),
        PolicyCase(.storeAll, .original, storesOriginalData: true),
        PolicyCase(.storeAll, .processedThenOriginal, storesOriginalData: true)
    ])
    func policyDecidesWhatDataTasksStore(_ policyCase: PolicyCase) async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = policyCase.policy
        }

        // WHEN
        for request in policyCase.requests.imageRequests {
            _ = try await pipeline.data(for: request)
        }

        // THEN the original data is written once at most
        let keys: Set<String> = policyCase.storesOriginalData ? [Test.url.absoluteString] : []
        #expect(Set(dataCache.store.keys) == keys)
        #expect(dataCache.writeCount == keys.count)
        #expect(encoder.encodeCount == 0)
    }

    /// The requests for `Test.url` that a row loads one after the other with a
    /// data cache policy, and whether the policy stores the original data.
    struct PolicyCase: Sendable, CustomStringConvertible {
        let policy: ImagePipeline.DataCachePolicy
        let requests: Requests
        let storesOriginalData: Bool

        init(_ policy: ImagePipeline.DataCachePolicy, _ requests: Requests, storesOriginalData: Bool) {
            self.policy = policy
            self.requests = requests
            self.storesOriginalData = storesOriginalData
        }

        var description: String {
            "\(policy), \(requests.rawValue)"
        }

        enum Requests: String, Sendable {
            case processed
            case original
            case processedThenOriginal = "processed then original"

            var imageRequests: [ImageRequest] {
                let processed = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
                let original = ImageRequest(url: Test.url)
                switch self {
                case .processed: return [processed]
                case .original: return [original]
                case .processedThenOriginal: return [processed, original]
                }
            }
        }
    }
}
