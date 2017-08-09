// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class RateLimiterTests: XCTestCase {
 
    // MARK: Thread Safety
    
    func testThreadSafety() {
        let scheduler = MockScheduler()
        let limiter = RateLimiter(scheduler: scheduler, rate: 10000, burst: 1000)
        
        // can't figure out how to put closures that accept 
        // escaping closures as parameters directly in the array
        struct Op {
            let closure: (@escaping () -> Void) -> Void
        }
        
        var ops = [Op]()
        
        ops.append(Op() { fulfill in
            limiter.execute(token: nil) { finish in
                sleep(UInt32(Double(rnd(10)) / 100.0))
                finish()
                fulfill()
            }
        })
        
        ops.append(Op() { fulfill in
            // cancel after executing
            let cts = CancellationTokenSource()
            limiter.execute(token: cts.token) { finish in
                sleep(UInt32(Double(rnd(10)) / 100.0))
                finish()
            }
            cts.cancel()
            fulfill() // we don't except fulfil
        })
        
        ops.append(Op() { fulfill in
            // cancel immediately
            let cts = CancellationTokenSource()
            cts.cancel()
            limiter.execute(token: cts.token) { finish in
                sleep(UInt32(Double(rnd(10)) / 100.0))
                finish()
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
                queue.maxConcurrentOperationCount = 50
                
                queue.addOperation {
                    ops.randomItem().closure(fulfill)
                }
            }
        }
        
        wait()
    }
}

private class MockScheduler: Nuke.AsyncScheduler {
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 50
        return queue
    }()
    
    fileprivate func execute(token: CancellationToken?, closure: @escaping (@escaping () -> Void) -> Void) {
        queue.addOperation {
            closure { return }
        }
    }
}
