// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class RateLimiterTests: XCTestCase {
 
    // MARK: Thread Safety
    
    func testThreadSafety() {
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
        
        wait()
    }
}
