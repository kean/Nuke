// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke


class RateLimiterTests: XCTestCase {
 
    // MARK: Thread Safety
    
    func testThreadSafety() {
        let limiter = RateLimiter(rate: 10000, burst: 1000)
        
        // can't figure out how to put closures that accept 
        // escaping closures as parameters directly in the array
        struct Op {
            let closure: (@escaping () -> Void) -> Void
        }
        
        var ops = [Op]()
        
        ops.append(Op() { fulfill in
            let cts = CancellationTokenSource()
            limiter.execute(token: cts.token) {
                sleep(UInt32(Double(rnd(10)) / 100.0))
                fulfill()
            }
        })
        
        ops.append(Op() { fulfill in
            // cancel after executing
            let cts = CancellationTokenSource()
            limiter.execute(token: cts.token) {
                sleep(UInt32(Double(rnd(10)) / 100.0))
            }
            cts.cancel()
            fulfill() // we don't except fulfil
        })
        
        ops.append(Op() { fulfill in
            // cancel immediately
            let cts = CancellationTokenSource()
            cts.cancel()
            limiter.execute(token: cts.token) {
                sleep(UInt32(Double(rnd(10)) / 100.0))
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
