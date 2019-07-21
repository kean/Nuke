// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

@testable import Nuke
import XCTest

class ThreadSafetyTests: XCTestCase {
    func testImagePipelineThreadSafety() {
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        _testPipelineThreadSafety(pipeline)

        wait(20) { _ in
            _ = (dataLoader, pipeline)
        }
    }

    func testSharingConfigurationBetweenPipelines() { // Especially operation queues
        var pipelines = [ImagePipeline]()

        let configuration = ImagePipeline.Configuration()

        pipelines.append(ImagePipeline(configuration: configuration))
        pipelines.append(ImagePipeline(configuration: configuration))
        pipelines.append(ImagePipeline(configuration: configuration))

        for pipeline in pipelines {
            _testPipelineThreadSafety(pipeline)
        }

        wait(20) { _ in
            _ = (pipelines)
        }
    }

    func _testPipelineThreadSafety(_ pipeline: ImagePipeline) {
        for _ in 0..<1000 {
            let expectation = self.expectation(description: "Finished")
            DispatchQueue.global().async {
                let request = ImageRequest(url: URL(string: "\(Test.url)/\(rnd(30))")!)
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
    }

    func testPreheaterThreadSafety() {
        let pipeline = MockImagePipeline {
            $0.imageCache = nil
        }
        let preheater = ImagePreheater(pipeline: pipeline)

        func makeRequests() -> [ImageRequest] {
            return (0...rnd(30)).map { _ in
                return ImageRequest(url: URL(string: "http://\(rnd(15))")!)
            }
        }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        for _ in 0...300 {
            queue.addOperation {
                preheater.stopPreheating(with: makeRequests())
                preheater.startPreheating(with: makeRequests())
            }
        }
        queue.waitUntilAllOperationsAreFinished()
    }

    func testImageCacheThreadSafety() {
        let cache = ImageCache()

        func rnd_cost() -> Int {
            return (2 + rnd(20)) * 1024 * 1024
        }

        var ops = [() -> Void]()

        for _ in 0..<10 { // those ops happen more frequently
            ops += [
                { cache[_request(index: rnd(10))] = Test.image },
                { cache[_request(index: rnd(10))] = nil },
                { let _ = cache[_request(index: rnd(10))] }
            ]
        }

        ops += [
            { cache.costLimit = rnd_cost() },
            { cache.countLimit = rnd(10) },
            { cache.trim(toCost: rnd_cost()) },
            { cache.removeAll() }
        ]

        #if os(iOS) || os(tvOS)
        ops.append {
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        }
        ops.append {
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        }
        #endif

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5

        for _ in 0..<10000 {
            queue.addOperation {
                ops.randomItem()()
            }
        }

        queue.waitUntilAllOperationsAreFinished()
    }

    // MARK: - DataCache

    func testDataCacheThreadSafety() {
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
                    let _ = cache["\(idx)"]
                }
                queue.addOperation {
                    cache["\(idx)"] = data
                    cache.flush()
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()
    }
}

final class RandomizedTests: XCTestCase {
    func testImagePipeline() {
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isRateLimiterEnabled = false
        }

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 8

        func every(_ count: Int) -> Bool {
            return rnd() % count == 0
        }

        func randomRequest() -> ImageRequest {
            let url = URL(string: "\(Test.url)/\(rnd(50))")!
            var request = ImageRequest(url: url)
            request.priority = every(2) ? .high : .normal
            if every(3) {
                let size = every(2) ? CGSize(width: 40, height: 40) : CGSize(width: 60, height: 60)
                request.processors = [ImageProcessor.Resize(size: size, contentMode: .aspectFit)]
            }
            if every(10) {
                request.options.loadKey = url
            }
            return request
        }

        func randomSleep() {
            let ms = TimeInterval(arc4random_uniform(100)) / 1000.0
            Thread.sleep(forTimeInterval: ms)
        }

        for _ in 0..<1000 {
            let expectation = self.expectation(description: "Finished")
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

        wait(100) { _ in
            _ = pipeline
        }
    }
}

private func _request(index: Int) -> ImageRequest {
    return ImageRequest(url: URL(string: "http://example.com/img\(index)")!)
}
