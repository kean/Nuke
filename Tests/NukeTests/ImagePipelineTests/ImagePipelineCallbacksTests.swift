// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Combine
import Foundation

@testable import Nuke

@ImagePipelineActor
@Suite class ImagePipelineCallbacksTests {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    init() {
        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Completion

    @Test func loadImageCallbackCalled() async throws {
        // When
        let response = try await withCheckedThrowingContinuation { continuation in
            pipeline.loadImage(with: Test.request) { result in
                #expect(Thread.isMainThread)
                continuation.resume(with: result)
            }
        }

        // Then
        #expect(response.image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    @Test func loadDataCallbackCalled() async throws {
        // When
        let response = try await withCheckedThrowingContinuation { continuation in
            pipeline.loadData(with: Test.request) { result in
                #expect(Thread.isMainThread)
                continuation.resume(with: result)
            }
        }

        // Then
        #expect(response.data.count == 22789)
    }

    // MARK: - Progress

    @Test func loadImageProgressReported() async {
        // Given
        let request = ImageRequest(url: Test.url)

        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let recordedProgress = Mutex<[ImageTask.Progress]>(wrappedValue: [])
        await withCheckedContinuation { continuation in
            pipeline.loadImage(
                with: request,
                progress: { _, completed, total in
                    // Then
                    #expect(Thread.isMainThread)
                    recordedProgress.withLock {
                        $0.append(ImageTask.Progress(completed: completed, total: total))
                    }
                },
                completion: { _ in
                    continuation.resume()
                }
            )
        }

        // Then
        #expect(recordedProgress.wrappedValue == [
            ImageTask.Progress(completed: 10, total: 20),
            ImageTask.Progress(completed: 20, total: 20)
        ])
    }

    @Test func loadDataProgressReported() async {
        // Given
        let request = ImageRequest(url: Test.url)

        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let recordedProgress = Mutex<[ImageTask.Progress]>(wrappedValue: [])
        await withCheckedContinuation { continuation in
            pipeline.loadData(
                with: request,
                progress: { completed, total in
                    // Then
                    #expect(Thread.isMainThread)
                    recordedProgress.withLock {
                        $0.append(ImageTask.Progress(completed: completed, total: total))
                    }
                },
                completion: { _ in
                    continuation.resume()
                }
            )
        }

        // Then
        #expect(recordedProgress.wrappedValue == [
            ImageTask.Progress(completed: 10, total: 20),
            ImageTask.Progress(completed: 20, total: 20)
        ])
    }

    // MARK: Error Handling

    @Test func dataLoadingFailedErrorReturned() async {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        let expectedError = NSError(domain: "t", code: 23, userInfo: nil)
        dataLoader.results[Test.url] = .failure(expectedError)

        // When
        let error = await withCheckedContinuation { continuation in
            pipeline.loadImage(with: Test.request) { result in
                switch result {
                case .success:
                    Issue.record("Unexpected success")
                case .failure(let error):
                    continuation.resume(returning: error)
                }
            }
        }

        // Then
        #expect(error == .dataLoadingFailed(error: expectedError))
    }
}
