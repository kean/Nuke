// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelinePreviewPolicyTests {

    // MARK: - Progressive JPEG (default policy = .incremental)

    @Test func progressiveJPEGDeliversPreviews() async throws {
        // GIVEN a progressive JPEG served in chunks with manual resume
        let dataLoader = MockProgressiveDataLoader()
        dataLoader.servesFirstChunkAutomatically = false
        let pipeline = dataLoader.makePipeline()

        // WHEN loading the image and collecting previews
        let task = pipeline.imageTask(with: Test.url)
        let stream = task.previews
        dataLoader.resume()
        var previews: [ImageResponse] = []
        for try await preview in stream {
            previews.append(preview)
            dataLoader.resume()
        }
        let finalImage = try await task.image

        // THEN previews are delivered (default policy is .incremental for progressive JPEG)
        #expect(previews.count >= 1)
        #expect(previews.allSatisfy { $0.container.isPreview })
        #expect(finalImage.sizeInPixels == CGSize(width: 450, height: 300))
    }

    // MARK: - Progressive JPEG with .disabled policy

    @Test func progressiveJPEGWithDisabledPolicyDeliversNoPreviews() async throws {
        // GIVEN a delegate that disables previews and data sent automatically
        let delegate = MockPreviewPolicyDelegate(policy: .disabled)
        let dataLoader = MockAutoDataLoader(
            data: Test.data(name: "progressive", extension: "jpeg")
        )
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.imageCache = nil
        }

        // WHEN loading the image
        let task = pipeline.imageTask(with: Test.url)
        var previews: [ImageResponse] = []
        for try await preview in task.previews {
            previews.append(preview)
        }
        let finalImage = try await task.image

        // THEN no previews are delivered
        #expect(previews.isEmpty)
        #expect(finalImage.sizeInPixels == CGSize(width: 450, height: 300))
    }

    // MARK: - Baseline JPEG (default policy = .disabled)

    @Test func baselineJPEGDeliversNoPreviewsByDefault() async throws {
        // GIVEN a baseline JPEG served incrementally (auto, no manual resume)
        let dataLoader = MockAutoDataLoader(
            data: Test.data(name: "baseline", extension: "jpeg")
        )
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.imageCache = nil
        }

        // WHEN loading the image and collecting previews
        let task = pipeline.imageTask(with: Test.url)
        var previews: [ImageResponse] = []
        for try await preview in task.previews {
            previews.append(preview)
        }
        let finalImage = try await task.image

        // THEN no previews because default policy for baseline JPEG is .disabled
        #expect(previews.isEmpty)
        #expect(finalImage.sizeInPixels.width > 0)
    }

    // MARK: - Baseline JPEG with .incremental policy

    @Test func baselineJPEGWithIncrementalPolicyDeliversPreviews() async throws {
        // GIVEN a delegate that forces .incremental for all images, and a
        // baseline JPEG served in two chunks with manual resume: Image I/O
        // needs roughly half of a baseline JPEG to produce a partial image,
        // and a third is sometimes too little on newer macOS releases
        let delegate = MockPreviewPolicyDelegate(policy: .incremental)
        let dataLoader = MockProgressiveDataLoader(data: Test.data(name: "baseline", extension: "jpeg"), chunkCount: 2)
        dataLoader.servesFirstChunkAutomatically = false
        let pipeline = dataLoader.makePipeline(delegate: delegate)

        // WHEN loading the image
        let task = pipeline.imageTask(with: Test.url)
        let stream = task.previews
        dataLoader.resume()
        var previews: [ImageResponse] = []
        for try await preview in stream {
            previews.append(preview)
            dataLoader.resume()
        }
        let finalImage = try await task.image

        // THEN previews are delivered because policy is .incremental
        #expect(previews.count >= 1)
        #expect(previews.allSatisfy { $0.container.isPreview })
        #expect(finalImage.sizeInPixels.width > 0)
    }

    // MARK: - Thumbnail Policy

    @Test func thumbnailPolicyDeliversASinglePreview() async throws {
        // GIVEN a delegate that asks for the embedded thumbnail
        let delegate = MockPreviewPolicyDelegate(policy: .thumbnail)
        let dataLoader = MockAutoDataLoader(
            data: Test.data(name: "progressive", extension: "jpeg"),
            chunkCount: 8
        )
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.imageCache = nil
        }

        // WHEN loading the image
        let task = pipeline.imageTask(with: Test.url)
        var previews: [ImageResponse] = []
        for try await preview in task.previews {
            previews.append(preview)
        }
        let finalImage = try await task.image

        // THEN the thumbnail is only ever generated once, no matter how many
        // chunks arrive
        #expect(previews.count == 1)
        #expect(previews.allSatisfy { $0.container.isPreview })
        #expect(previews.first?.container.userInfo[.scanNumberKey] as? Int == 1)
        #expect(finalImage.sizeInPixels == CGSize(width: 450, height: 300))
    }

    @Test func thumbnailPolicyDeliversNoPreviewsWhenThereIsNoThumbnail() async throws {
        // GIVEN an image with no embedded thumbnail
        let delegate = MockPreviewPolicyDelegate(policy: .thumbnail)
        let dataLoader = MockAutoDataLoader(
            data: Test.data(name: "img_751", extension: "heic")
        )
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.imageCache = nil
        }

        // WHEN loading the image
        let task = pipeline.imageTask(with: Test.url)
        var previews: [ImageResponse] = []
        for try await preview in task.previews {
            previews.append(preview)
        }

        // THEN
        #expect(previews.isEmpty)
        _ = try await task.image
    }

    // MARK: - GIF

    @Test func gifDeliversPreviewsByDefault() async throws {
        // GIVEN a GIF served in chunks (default policy is .incremental for GIF)
        let dataLoader = MockAutoDataLoader(
            data: Test.data(name: "cat", extension: "gif"),
            chunkCount: 8
        )
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.imageCache = nil
        }

        // WHEN loading the image
        let task = pipeline.imageTask(with: Test.url)
        var previews: [ImageResponse] = []
        for try await preview in task.previews {
            previews.append(preview)
        }

        // THEN a single preview is delivered
        #expect(previews.count == 1)
        #expect(previews.allSatisfy { $0.container.isPreview })
        _ = try await task.image
    }

    @Test func gifWithDisabledPolicyDeliversNoPreviews() async throws {
        // GIVEN a delegate that disables previews and a GIF served in chunks
        let delegate = MockPreviewPolicyDelegate(policy: .disabled)
        let dataLoader = MockAutoDataLoader(
            data: Test.data(name: "cat", extension: "gif"),
            chunkCount: 8
        )
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.imageCache = nil
        }

        // WHEN loading the image
        let task = pipeline.imageTask(with: Test.url)
        var previews: [ImageResponse] = []
        for try await preview in task.previews {
            previews.append(preview)
        }

        // THEN no previews are delivered
        #expect(previews.isEmpty)
        let response = try await task.response
        #expect(response.container.type == .gif)
    }

    // MARK: - Policy that only resolves to .incremental on later chunks

    @Test func policyIsReevaluatedWhenMoreDataArrives() async throws {
        // GIVEN a delegate that can't tell the image is progressive from the
        // first chunk – the norm for progressive JPEGs with large EXIF/ICC
        // preambles, where `PreviewPolicy.default(for:)` returns `.disabled`
        // until `kCGImagePropertyJFIFIsProgressive` can be parsed
        let delegate = MockPreviewPolicyDelegate(policies: [.disabled, .incremental])
        let dataLoader = MockAutoDataLoader(
            data: Test.data(name: "progressive", extension: "jpeg")
        )
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.imageCache = nil
        }

        // WHEN loading the image
        let task = pipeline.imageTask(with: Test.url)
        var previews: [ImageResponse] = []
        for try await preview in task.previews {
            previews.append(preview)
        }
        let finalImage = try await task.image

        // THEN the policy the pipeline computes for the later chunks is used
        // and previews are delivered instead of the first chunk's `.disabled`
        // permanently switching them off
        #expect(delegate.policyRequestCount >= 2)
        #expect(previews.count >= 1)
        #expect(previews.allSatisfy { $0.container.isPreview })
        #expect(finalImage.sizeInPixels == CGSize(width: 450, height: 300))
    }

    @Test func policyIsNotReevaluatedForEveryChunk() async throws {
        // GIVEN a policy that never resolves to anything other than `.disabled`
        // and data served in many chunks
        let delegate = MockPreviewPolicyDelegate(policy: .disabled)
        let dataLoader = MockAutoDataLoader(
            data: Test.data(name: "progressive", extension: "jpeg"),
            chunkCount: 16
        )
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.imageCache = nil
        }

        // WHEN loading the image
        let task = pipeline.imageTask(with: Test.url)
        var previews: [ImageResponse] = []
        for try await preview in task.previews {
            previews.append(preview)
        }
        let finalImage = try await task.image

        // THEN the pipeline retries a few times as more data arrives, but
        // doesn't re-evaluate the policy for every chunk – each evaluation
        // parses the partially downloaded data
        #expect(delegate.policyRequestCount > 1)
        #expect(delegate.policyRequestCount <= 6)
        #expect(previews.isEmpty)
        #expect(finalImage.sizeInPixels == CGSize(width: 450, height: 300))
    }

    @Test func previewPolicyIsReevaluatedOnlyWhenTheDataDoubles() async throws {
        // GIVEN a policy that never resolves to anything other than `.disabled`
        // and data served in 20 chunks of the same size. The default decoder
        // looks at partial data on the pipeline's actor, so no chunk is
        // skipped while another one is being decoded.
        let delegate = MockPreviewPolicyDelegate(policy: .disabled)
        let dataLoader = MockAutoDataLoader(
            data: Test.data(name: "progressive", extension: "jpeg"),
            chunkCount: 20
        )
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.imageCache = nil
        }

        // WHEN loading the image
        _ = try await pipeline.image(for: Test.url)

        // THEN the policy is evaluated for the 1st, 2nd, 4th, 8th and 16th
        // chunk, each time the data has doubled since the last evaluation
        #expect(delegate.policyRequestCount == 5)
    }

    @Test func previewPolicyReevaluationIsCapped() async throws {
        // GIVEN a policy that never resolves to anything other than `.disabled`
        // and data served in 100 chunks of the same size
        let delegate = MockPreviewPolicyDelegate(policy: .disabled)
        let dataLoader = MockAutoDataLoader(
            data: Test.data(name: "progressive", extension: "jpeg"),
            chunkCount: 100
        )
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.imageCache = nil
        }

        // WHEN loading the image
        _ = try await pipeline.image(for: Test.url)

        // THEN the policy is evaluated for the 1st, 2nd, 4th, 8th, 16th and
        // 32nd chunk, and not for the 64th, although the data has doubled
        // again by then
        #expect(delegate.policyRequestCount == 6)
    }
}

// MARK: - Helpers

/// Serves data in chunks automatically without requiring manual resume calls.
private final class MockAutoDataLoader: DataLoading, @unchecked Sendable {
    let data: Data
    let chunkCount: Int
    let urlResponse: HTTPURLResponse

    init(data: Data, chunkCount: Int = 3) {
        self.data = data
        self.chunkCount = chunkCount
        self.urlResponse = HTTPURLResponse(
            url: Test.url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(data.count)"]
        )!
    }

    func loadData(with request: URLRequest,
                  didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                  completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let chunks = Array(_createChunks(for: data, size: data.count / chunkCount))
        let response = urlResponse
        DispatchQueue.main.async {
            for chunk in chunks {
                didReceiveData(chunk, response)
            }
            completion(nil)
        }
        return AnonymousCancellable {}
    }
}
