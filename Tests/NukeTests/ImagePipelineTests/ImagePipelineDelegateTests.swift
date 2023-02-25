// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineDelegateTests: XCTestCase {
    private var dataLoader: MockDataLoader!
    private var dataCache: MockDataCache!
    private var pipeline: ImagePipeline!
    private var delegate: MockImagePipelineDelegate!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        dataCache = MockDataCache()
        delegate = MockImagePipelineDelegate()

        pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.dataCachePolicy = .automatic
            $0.imageCache = nil
            $0.debugIsSyncImageEncoding = true
        }
    }

    @MainActor
    func testCustomizingDataCacheKey() throws {
        // GIVEN
        let imageURLSmall = URL(string: "https://example.com/image-01-small.jpeg")!
        let imageURLMedium = URL(string: "https://example.com/image-01-medium.jpeg")!

        dataLoader.results[imageURLMedium] = .success(
            (Test.data, URLResponse(url: imageURLMedium, mimeType: "jpeg", expectedContentLength: Test.data.count, textEncodingName: nil))
        )

        // GIVEN image is loaded from medium size URL and saved in cache using imageId "image-01-small"
        let requestA = ImageRequest(
            url: imageURLMedium,
            processors: [.resize(width: 44)],
            userInfo: ["imageId": "image-01-small"]
        )
        expect(pipeline).toLoadImage(with: requestA)
        wait()

        let data = try XCTUnwrap(dataCache.cachedData(for: "image-01-small"))
        let image = try XCTUnwrap(PlatformImage(data: data))
        XCTAssertEqual(image.sizeInPixels.width, 44 * Screen.scale)

        // GIVEN a request for a small image
        let requestB = ImageRequest(
            url: imageURLSmall,
            userInfo: ["imageId": "image-01-small"]
        )

        // WHEN/THEN the image is returned from the disk cache
        expect(pipeline).toLoadImage(with: requestB, completion: { result in
            guard let image = result.value?.image else {
                return XCTFail()
            }
            XCTAssertEqual(image.sizeInPixels.width, 44 * Screen.scale)
        })
        wait()
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
    }

    func testDataIsStoredInCache() {
        // WHEN
        expect(pipeline).toLoadImage(with: Test.request)

        // THEN
        wait { _ in
            XCTAssertFalse(self.dataCache.store.isEmpty)
        }
    }

    func testDataIsStoredInCacheWhenCacheDisabled() {
        // WHEN
        delegate.isCacheEnabled = false
        expect(pipeline).toLoadImage(with: Test.request)

        // THEN
        wait { _ in
            XCTAssertTrue(self.dataCache.store.isEmpty)
        }
    }
}

private final class MockImagePipelineDelegate: ImagePipelineDelegate, @unchecked Sendable {
    var isCacheEnabled = true

    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        request.userInfo["imageId"] as? String
    }

    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline, completion: @escaping (Data?) -> Void) {
        completion(isCacheEnabled ? data : nil)
    }
}
