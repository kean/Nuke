// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

@testable import Nuke
import Testing
import Foundation

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

@Suite struct ThreadSafetyTests {
    @Test func imagePipelineThreadSafety() async {
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        await performPipelineThreadSafetyTest(pipeline)

        _ = (dataLoader, pipeline)
    }

    @Test func sharingConfigurationBetweenPipelines() async { // Especially operation queues
        var configuration = ImagePipeline.Configuration()
        configuration.dataLoader = MockDataLoader()
        configuration.imageCache = nil

        let pipelines = [
            ImagePipeline(configuration: configuration),
            ImagePipeline(configuration: configuration),
            ImagePipeline(configuration: configuration)
        ]

        for pipeline in pipelines {
            await performPipelineThreadSafetyTest(pipeline)
        }

        _ = pipelines
    }

    @Test func prefetcherThreadSafety() {
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }

        let prefetcher = ImagePrefetcher(pipeline: pipeline)

        @Sendable func makeRequests() -> [ImageRequest] {
            return (0...Int.random(in: 0..<30)).map { _ in
                return ImageRequest(url: URL(string: "http://\(Int.random(in: 0..<15))")!)
            }
        }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        for _ in 0...300 {
            queue.addOperation {
                prefetcher.stopPrefetching(with: makeRequests())
                prefetcher.startPrefetching(with: makeRequests())
            }
        }
        queue.waitUntilAllOperationsAreFinished()
    }

    @Test func imageCacheThreadSafety() {
        let cache = ImageCache()

        @Sendable func rnd_cost() -> Int {
            return (2 + Int.random(in: 0..<20)) * 1024 * 1024
        }

        var ops = [@Sendable () -> Void]()

        for _ in 0..<10 { // those ops happen more frequently
            ops += [
                { cache[_request(index: Int.random(in: 0..<10))] = ImageContainer(image: Test.image) },
                { cache[_request(index: Int.random(in: 0..<10))] = nil },
                { let _ = cache[_request(index: Int.random(in: 0..<10))] }
            ]
        }

        ops += [
            { cache.trim(toCost: rnd_cost()) },
            { cache.removeAll() }
        ]

#if os(iOS) || os(tvOS) || os(visionOS)
        ops.append {
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        }
        ops.append {
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        }
#endif

        let finalOps = ops
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5

        for _ in 0..<10000 {
            queue.addOperation {
                finalOps.randomElement()?()
            }
        }

        queue.waitUntilAllOperationsAreFinished()
    }

    // MARK: - DataCache

    @Test func dataCacheThreadSafety() throws {
        let cache = try DataCache(name: UUID().uuidString, filenameGenerator: { $0 })

        let data = Data(repeating: 1, count: 256 * 1024)

        for idx in 0..<500 {
            cache["\(idx)"] = data
        }
        cache.flush()

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5

        for _ in 0..<5 {
            for idx in 0..<500 {
                queue.addOperation {
                    _ = cache["\(idx)"]
                }
                queue.addOperation {
                    cache["\(idx)"] = data
                    cache.flush()
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()
    }

    @Test func dataCacheMultipleThreadAccess() async throws {
        let cache = try DataCache(name: UUID().uuidString)

        let aURL = URL(string: "https://example.com/image-01-small.jpeg")!
        let imageData = Test.data(name: "fixture", extension: "jpeg")

        let expectation = TestExpectation()

        let pipeline = ImagePipeline {
            $0.dataCache = cache
            $0.dataLoader = MockDataLoader()
        }
        pipeline.cache.storeCachedData(imageData, for: ImageRequest(url: aURL))
        pipeline.loadImage(with: aURL) { result in
            switch result {
            case .success(let response):
                if response.cacheType == .memory || response.cacheType == .disk {
                    expectation.fulfill()
                } else {
                    Issue.record("didn't load that just cached image data: \(response)")
                }
            case .failure:
                Issue.record("didn't load that just cached image data")
            }
        }

        await expectation.wait()

        try? FileManager.default.removeItem(at: cache.path)
    }
}

@Suite struct OperationThreadSafetyTests {
    @Test func operation() {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 10

        DispatchQueue.concurrentPerform(iterations: 5) { _ in
            for index in 0..<500 {
                let operation = Operation(starter: { finish in
                    Thread.sleep(forTimeInterval: Double.random(in: 1...10) / 1000.0)
                    finish()
                })
                if index % 3 == 0 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int.random(in: 5...10))) {
                        operation.cancel()
                        operation.cancel()
                        operation.cancel()
                    }
                }
                queue.addOperation(operation)
            }
        }
        queue.waitUntilAllOperationsAreFinished()
    }
}

@Suite struct RandomizedTests {
    @Test func imagePipeline() async {
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isRateLimiterEnabled = false
        }

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 8

        @Sendable func every(_ count: Int) -> Bool {
            return Int.random(in: 0..<Int.max) % count == 0
        }

        @Sendable func randomRequest() -> ImageRequest {
            let url = URL(string: "\(Test.url)/\(Int.random(in: 0..<50))")!
            var request = ImageRequest(url: url)
            request.priority = every(2) ? .high : .normal
            if every(3) {
                let size = every(2) ? CGSize(width: 40, height: 40) : CGSize(width: 60, height: 60)
                request.processors = [ImageProcessors.Resize(size: size, contentMode: .aspectFit)]
            }
            return request
        }

        @Sendable func randomSleep() {
            let ms = TimeInterval.random(in: 0 ..< 100) / 1000.0
            Thread.sleep(forTimeInterval: ms)
        }

        let group = DispatchGroup()

        for _ in 0..<1000 {
            group.enter()
            queue.addOperation {
                randomSleep()

                let request = randomRequest()
                let shouldCancel = every(3)

                let task = pipeline.loadImage(with: request) { _ in
                    if !shouldCancel {
                        group.leave()
                    }
                }

                if shouldCancel {
                    queue.addOperation {
                        randomSleep()
                        task.cancel()
                        group.leave()
                    }
                }

                if every(10) {
                    queue.addOperation {
                        randomSleep()
                        let priority: ImageRequest.Priority = every(2) ? .veryHigh : .veryLow
                        task.priority = priority
                    }
                }
            }
        }

        await withCheckedContinuation { continuation in
            group.notify(queue: .global()) {
                continuation.resume()
            }
        }

        _ = pipeline
    }
}

private func performPipelineThreadSafetyTest(_ pipeline: ImagePipeline) async {
    let group = DispatchGroup()
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 16

    for _ in 0..<1000 {
        group.enter()
        queue.addOperation {
            let url = URL(fileURLWithPath: "\(Int.random(in: 0..<30))")
            let request = ImageRequest(url: url)
            let shouldCancel = Int.random(in: 0..<3) == 0

            let task = pipeline.loadImage(with: request) { _ in
                if shouldCancel {
                    // do nothing, we don't expect completion on cancel
                } else {
                    group.leave()
                }
            }

            if shouldCancel {
                task.cancel()
                group.leave()
            }
        }
    }

    await withCheckedContinuation { continuation in
        group.notify(queue: .global()) {
            continuation.resume()
        }
    }
}

private func _request(index: Int) -> ImageRequest {
    return ImageRequest(url: URL(string: "http://example.com/img\(index)")!)
}
