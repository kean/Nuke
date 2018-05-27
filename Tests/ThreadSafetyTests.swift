// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

@testable import Nuke
import XCTest

class ThreadSafetyTests: XCTestCase {
    func testImagePipelineThreadSafety() {
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        for _ in 0..<500 {
            expect { fulfill in
                DispatchQueue.global().async {
                    let request = ImageRequest(url: URL(string: "\(defaultURL)/\(rnd(30))")!)
                    let shouldCancel = rnd(3) == 0

                    let task = pipeline.loadImage(with: request) { _,_ in
                        if shouldCancel {
                            // do nothing, we don't expect completion on cancel
                        } else {
                            fulfill()
                        }
                    }

                    if shouldCancel {
                        task.cancel()
                        fulfill()
                    }
                }
            }
        }

        wait(20) { _ in
            _ = (dataLoader, pipeline)
        }
    }

    func testPreheaterThreadSafety() {
        let pipeline = MockImagePipeline()
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

    func testCancellationTokenThreadSafety() {
        for _ in 0..<100 {
            let cts = _CancellationTokenSource()

            for _ in 0...100 {
                expect { fulfill in
                    DispatchQueue.global().async {
                        if rnd(4) == 0 {
                            cts.cancel()
                            fulfill()
                        } else {
                            cts.token.register {
                                fulfill()
                            }
                        }
                    }
                }
            }
        }

        wait(20)
    }

    func testRateLimiterThreadSafety() {
        let limiter = RateLimiter(queue: DispatchQueue(label: "RateLimiterTests.testThreadSafety"), rate: 10000, burst: 1000)

        // can't figure out how to put closures that accept
        // escaping closures as parameters directly in the array
        struct Op {
            let closure: (@escaping () -> Void) -> Void
        }

        var ops = [Op]()

        ops.append(Op() { fulfill in
            let cts = _CancellationTokenSource()
            limiter.execute(token: cts.token) {
                DispatchQueue.global().async {
                    fulfill()
                }
            }
        })

        ops.append(Op() { fulfill in
            // cancel after executing
            let cts = _CancellationTokenSource()
            limiter.execute(token: cts.token) {
                return
            }
            cts.cancel()
            fulfill() // we don't except fulfil
        })

        ops.append(Op() { fulfill in
            // cancel immediately
            let cts = _CancellationTokenSource()
            cts.cancel()
            limiter.execute(token: cts.token) {
                XCTFail() // must not be executed
            }
            fulfill()
        })

        for _ in 0..<5000 {
            expect { fulfill in
                let queue = OperationQueue()

                // RateLimiter is not designed (unlike user-facing classes) to
                // handle unlimited pressure from the outside, thus we limit
                // the number of concurrent ops
                queue.maxConcurrentOperationCount = 40

                queue.addOperation {
                    ops.randomItem().closure(fulfill)
                }
            }
        }

        wait(20)
    }

    func testImageCacheThreadSafety() {
        let cache = ImageCache()

        func rnd_cost() -> Int {
            return (2 + rnd(20)) * 1024 * 1024
        }

        var ops = [() -> Void]()

        for _ in 0..<10 { // those ops happen more frequently
            ops += [
                { cache[_request(index: rnd(10))] = defaultImage },
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
            NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil)
        }
        ops.append {
            NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
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
}

private func _request(index: Int) -> ImageRequest {
    return ImageRequest(url: URL(string: "http://example.com/img\(index)")!)
}
