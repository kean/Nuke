// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
import Combine

@testable import Nuke

@MainActor
@Suite class ImagePipelinePublisherProgressiveDecodingTests {
    private var dataLoader: MockProgressiveDataLoader!
    private var imageCache: MockImageCache!
    private var pipeline: ImagePipeline!
    private var cancellable: AnyCancellable?

    init() {
        dataLoader = MockProgressiveDataLoader()

        imageCache = MockImageCache()
        ResumableDataStorage.shared.removeAllResponses()

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.isResumableDataEnabled = false
            $0.isProgressiveDecodingEnabled = true
            $0.isStoringPreviewsInMemoryCache = true
        }
    }

    @Test func imagePreviewsAreDelivered() async throws {
        let expectation = AsyncExpectation<Void>()
        var output: [ImageResponse] = []

        // When
        cancellable = pipeline.imagePublisher(with: Test.url).sink(receiveCompletion: { completion in
            switch completion {
            case .failure:
                Issue.record()
            case .finished:
                expectation.fulfill()
            }

        }, receiveValue: { response in
            output.append(response)
            self.dataLoader.resume()
        })

        await expectation.wait()

        // Then
        guard output.count == 3 else {
            Issue.record()
            return
        }

        #expect(output[0].isPreview == true)
        #expect(output[1].isPreview == true)
        #expect(output[2].isPreview == false)

    }

    @Test func imagePreviewsAreDeliveredFromMemoryCacheSynchronously() async {
        // Given
        pipeline.cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        let expectation = AsyncExpectation<Void>()
        var isFirstPreviewProduced = false
        var output: [ImageResponse] = []

        // When
        let publisher = pipeline.imagePublisher(with: Test.url)
        cancellable =  publisher.sink(receiveCompletion: { completion in
            switch completion {
            case .failure:
                Issue.record()
            case .finished:
                expectation.fulfill()
            }

        }, receiveValue: { response in
            isFirstPreviewProduced = true
            output.append(response)
            self.dataLoader.resume()
        })

        // Then first preview is delived synchronously
        #expect(isFirstPreviewProduced)

        await expectation.wait()

        // Then
        guard output.count == 4 else {
            Issue.record()
            return
        }

        // 1 preview from sync cache lookup
        // 1 preview from async cache lookup (we don't want it really though)
        // 2 previews from data loading
        // 1 final image
        // we also expect resumable data to kick in for real downloads
        #expect(output[0].isPreview == true)
        #expect(output[1].isPreview == true)
        #expect(output[2].isPreview == true)
        #expect(output[3].isPreview == false)
    }
}
