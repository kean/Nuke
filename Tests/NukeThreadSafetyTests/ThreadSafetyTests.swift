// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import UIKit

@testable import Nuke

@ImagePipelineActor
@Suite struct ThreadSafetyTests {
    @Test func imagePipelineThreadSafety() async {
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        let expectation = _testPipelineThreadSafety(pipeline)
        await expectation.wait()

        _ = (dataLoader, pipeline)
    }

    @Test func sharingConfigurationBetweenPipelines() async { // Especially operation queues
        var pipelines = [ImagePipeline]()

        var configuration = ImagePipeline.Configuration()
        configuration.dataLoader = MockDataLoader()
        configuration.imageCache = nil

        pipelines.append(ImagePipeline(configuration: configuration))
        pipelines.append(ImagePipeline(configuration: configuration))
        pipelines.append(ImagePipeline(configuration: configuration))

        var expectations: [AsyncExpectation<Void>] = []

        for pipeline in pipelines {
            let expectation = _testPipelineThreadSafety(pipeline)
            expectations.append(expectation)
        }

        for expectation in expectations {
            await expectation.wait()
        }

        _ = (pipelines)
    }

    func _testPipelineThreadSafety(_ pipeline: ImagePipeline) -> AsyncExpectation<Void> {
        let expectation = AsyncExpectation(expectedFulfillmentCount: 1000)

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 16

        for _ in 0..<1000 {
            queue.addOperation {
                let url = URL(fileURLWithPath: "\(rnd(30))")
                let request = ImageRequest(url: url)
                let shouldCancel = rnd(3) == 0

                let task = pipeline.loadImage(with: request) { _ in
                    if shouldCancel {
                        // do nothing, we don't expect completion on cancel
                    } else {
                        expectation.fulfill()
                    }
                }

                if shouldCancel {
                    task.cancel()
                    expectation.fulfill()
                }
            }
        }

        return expectation
    }

    @Test func prefetcherThreadSafety() {
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }

        let prefetcher = ImagePrefetcher(pipeline: pipeline)

        @Sendable func makeRequests() -> [ImageRequest] {
            return (0...rnd(30)).map { _ in
                ImageRequest(url: URL(string: "http://\(rnd(15))")!)
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

        func rnd_cost() -> Int {
            return (2 + rnd(20)) * 1024 * 1024
        }

        var ops = [() -> Void]()

        for _ in 0..<10 { // those ops happen more frequently
            ops += [
                { cache[_request(index: rnd(10))] = ImageContainer(image: Test.image) },
                { cache[_request(index: rnd(10))] = nil },
                { let _ = cache[_request(index: rnd(10))] }
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

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5

        let operations = ops
        for _ in 0..<10000 {
            queue.addOperation {
                operations.randomElement()?()
            }
        }

        queue.waitUntilAllOperationsAreFinished()
    }

    // MARK: - DataCache

    @Test func dataCacheThreadSafety() {
        let cache = try! DataCache(name: UUID().uuidString, filenameGenerator: { $0 })

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

        let expectSuccessFromCache = AsyncExpectation<Void>()

        let pipeline = ImagePipeline {
            $0.dataCache = cache
            $0.dataLoader = MockDataLoader()
        }
        pipeline.cache.storeCachedData(imageData, for: ImageRequest(url: aURL))
        pipeline.loadImage(with: aURL) { result in
            switch result {
            case .success(let response):
                if response.cacheType == .memory || response.cacheType == .disk {
                    expectSuccessFromCache.fulfill()
                } else {
                    Issue.record("didn't load that just cached image data: \(response)")
                }
            case .failure:
                Issue.record("didn't load that just cached image data")
            }
        }

        await expectSuccessFromCache.wait()

        try? FileManager.default.removeItem(at: cache.path)
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
            Int.random(in: 0 ..< .max) % count == 0
        }

        @Sendable func randomRequest() -> ImageRequest {
            let url = URL(string: "\(Test.url)/\(rnd(50))")!
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

        let expectation = AsyncExpectation(expectedFulfillmentCount: 1000)

        for _ in 0..<1000 {
            queue.addOperation {
                randomSleep()

                let request = randomRequest()

                let shouldCancel = every(3)

                let task = pipeline.loadImage(with: request) { _ in
                    if shouldCancel {
                        // do nothing, we don't expect completion on cancel
                    } else {
                        expectation.fulfill()
                    }
                }

                if shouldCancel {
                    queue.addOperation {
                        randomSleep()
                        task.cancel()
                        expectation.fulfill()
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

        await expectation.wait()
        _ = pipeline
    }
}

private func _request(index: Int) -> ImageRequest {
    ImageRequest(url: URL(string: "http://example.com/img\(index)")!)
}
