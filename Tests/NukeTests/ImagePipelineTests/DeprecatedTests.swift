// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(2)))
struct DeprecationTests {
    private let pipeline: ImagePipeline
    private let dataLoader: MockDataLoader

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - loadImage

    @Test func loadImageWithURL() async {
        dataLoader.isSuspended = true
        let result: Result<ImageResponse, ImagePipeline.Error> = await withCheckedContinuation { continuation in
            pipeline.loadImage(with: Test.url) { result in
                continuation.resume(returning: result)
            }
            dataLoader.isSuspended = false
        }
        #expect(result.isSuccess)
    }

    @Test func loadImageWithRequest() async {
        dataLoader.isSuspended = true
        let taskRef = Ref<ImageTask?>(nil)
        let stateInsideCallback = Ref<ImageTask.State>(.running)
        let result: Result<ImageResponse, ImagePipeline.Error> = await withCheckedContinuation { continuation in
            taskRef.value = pipeline.loadImage(with: Test.request) { result in
                stateInsideCallback.value = taskRef.value!.state
                continuation.resume(returning: result)
            }
            dataLoader.isSuspended = false
        }
        #expect(result.isSuccess)
        #expect(stateInsideCallback.value == .completed)
    }

    @Test func loadImageCompletionOnMainThread() async {
        dataLoader.isSuspended = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.loadImage(with: Test.request) { _ in
                #expect(Thread.isMainThread)
                continuation.resume()
            }
            dataLoader.isSuspended = false
        }
    }

    @Test func loadImageProgress() async {
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        let progressValues = Ref<[(Int64, Int64)]>([])
        dataLoader.isSuspended = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.loadImage(
                with: Test.request,
                progress: { _, completed, total in
                    #expect(Thread.isMainThread)
                    progressValues.value.append((completed, total))
                },
                completion: { _ in continuation.resume() }
            )
            dataLoader.isSuspended = false
        }
        #expect(progressValues.value.count == 2)
        #expect(progressValues.value[0] == (10, 20))
        #expect(progressValues.value[1] == (20, 20))
    }

    @Test func loadImageCancellation() async {
        dataLoader.isSuspended = true
        let task = await withCheckedContinuation { (continuation: CheckedContinuation<ImageTask, Never>) in
            let task = pipeline.loadImage(with: Test.request) { _ in
                Issue.record("Should not be called")
            }
            Task { @ImagePipelineActor in
                task.cancel()
                continuation.resume(returning: task)
            }
        }
        #expect(task.state == .cancelled)
    }

    @Test func loadImageCancellationCompletionNotCalled() async {
        dataLoader.isSuspended = true
        let completionCalled = Ref(false)
        let task = pipeline.loadImage(with: Test.request) { _ in
            completionCalled.value = true
        }
        task.cancel()
        // Wait for the pipeline actor to process cancellation and dispatch events
        await Task { @ImagePipelineActor in }.value
        // Simulate data arriving after cancellation
        dataLoader.isSuspended = false
        // Flush any DispatchQueue.main.async callbacks
        await MainActor.run {}
        #expect(!completionCalled.value)
        #expect(task.state == .cancelled)
    }

    // MARK: - loadData

    @Test func loadData() async {
        dataLoader.isSuspended = true
        let result: Result<(data: Data, response: URLResponse?), ImagePipeline.Error> = await withCheckedContinuation { continuation in
            pipeline.loadData(with: Test.request) { result in
                continuation.resume(returning: result)
            }
            dataLoader.isSuspended = false
        }
        #expect((try? result.get().data.count) == 22789)
    }

    @Test func loadDataCompletionOnMainThread() async {
        dataLoader.isSuspended = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.loadData(with: Test.request) { _ in
                #expect(Thread.isMainThread)
                continuation.resume()
            }
            dataLoader.isSuspended = false
        }
    }

    @Test func loadDataProgress() async {
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        let progressValues = Ref<[(Int64, Int64)]>([])
        dataLoader.isSuspended = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.loadData(
                with: Test.request,
                progress: { completed, total in
                    #expect(Thread.isMainThread)
                    progressValues.value.append((completed, total))
                },
                completion: { _ in continuation.resume() }
            )
            dataLoader.isSuspended = false
        }
        #expect(progressValues.value.count == 2)
        #expect(progressValues.value[0] == (10, 20))
        #expect(progressValues.value[1] == (20, 20))
    }
}
