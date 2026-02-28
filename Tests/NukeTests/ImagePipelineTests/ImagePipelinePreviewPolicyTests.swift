// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite struct ImagePipelinePreviewPolicyTests {

    // MARK: - Progressive JPEG (default policy = .incremental)

    @Test func progressiveJPEGDeliversPreviews() async throws {
        // GIVEN a progressive JPEG served in chunks with manual resume
        let dataLoader = MockProgressiveDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.imageCache = nil
        }

        // WHEN loading the image and collecting previews
        let task = pipeline.imageTask(with: Test.url)
        var previews: [ImageResponse] = []
        for try await preview in task.previews {
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
        let delegate = PreviewPolicyDelegate(policy: .disabled)
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
        // GIVEN a delegate that forces .incremental for all images
        let delegate = PreviewPolicyDelegate(policy: .incremental)
        let dataLoader = MockBaselineDataLoader()
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
            dataLoader.resume()
        }
        let finalImage = try await task.image

        // THEN previews are delivered because policy is .incremental
        #expect(previews.count >= 1)
        #expect(previews.allSatisfy { $0.container.isPreview })
        #expect(finalImage.sizeInPixels.width > 0)
    }
}

// MARK: - Helpers

/// A delegate that returns a fixed preview policy for all requests.
private final class PreviewPolicyDelegate: ImagePipelineDelegate, @unchecked Sendable {
    let policy: ImagePipeline.PreviewPolicy

    init(policy: ImagePipeline.PreviewPolicy) {
        self.policy = policy
    }

    func previewPolicy(for context: ImageDecodingContext, pipeline: ImagePipeline) -> ImagePipeline.PreviewPolicy {
        policy
    }
}

/// Serves data in chunks automatically without requiring manual resume calls.
private final class MockAutoDataLoader: DataLoading, @unchecked Sendable {
    let data: Data
    let urlResponse: HTTPURLResponse

    init(data: Data) {
        self.data = data
        self.urlResponse = HTTPURLResponse(
            url: Test.url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(data.count)"]
        )!
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> Cancellable {
        let chunks = Array(_createChunks(for: data, size: data.count / 3))
        let response = urlResponse
        DispatchQueue.main.async {
            for chunk in chunks {
                didReceiveData(chunk, response)
            }
            completion(nil)
        }
        return _Task()
    }

    private class _Task: Cancellable, @unchecked Sendable {
        func cancel() {}
    }
}

/// Serves a baseline JPEG in chunks with manual resume control.
private final class MockBaselineDataLoader: DataLoading, @unchecked Sendable {
    let urlResponse: HTTPURLResponse
    var chunks: [Data]
    let data = Test.data(name: "baseline", extension: "jpeg")

    private var didReceiveData: (Data, URLResponse) -> Void = { _, _ in }
    private var completion: (Error?) -> Void = { _ in }

    init() {
        self.urlResponse = HTTPURLResponse(
            url: Test.url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(data.count)"]
        )!
        self.chunks = Array(_createChunks(for: data, size: data.count / 3))
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> Cancellable {
        self.didReceiveData = didReceiveData
        self.completion = completion
        self.resume()
        return _Task()
    }

    func resume() {
        DispatchQueue.main.async {
            if let chunk = self.chunks.first {
                self.chunks.removeFirst()
                self.didReceiveData(chunk, self.urlResponse)
                if self.chunks.isEmpty {
                    self.completion(nil)
                }
            }
        }
    }

    private class _Task: Cancellable, @unchecked Sendable {
        func cancel() {}
    }
}
