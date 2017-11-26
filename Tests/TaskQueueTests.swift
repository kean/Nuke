// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke


class TaskQueueTests: XCTestCase {

    // MARK: Thread Safety

    func testThreadSafety() {
        let queue = TaskQueue(maxConcurrentTaskCount: 10)

        // can't figure out how to put closures that accept
        // escaping closures as parameters directly in the array
        struct Op {
            let closure: (@escaping () -> Void) -> Void
        }

        var ops = [Op]()

        ops.append(Op() { fulfill in
            let cts = CancellationTokenSource()
            queue.execute(token: cts.token) {
                sleep(UInt32(Double(rnd(10)) / 100.0))
                fulfill()
                $0()
            }
        })

        ops.append(Op() { fulfill in
            // cancel after executing
            let cts = CancellationTokenSource()
            queue.execute(token: cts.token) {
                sleep(UInt32(Double(rnd(10)) / 100.0))
                $0()
            }
            cts.cancel()
            fulfill() // we don't except fulfil
        })

        ops.append(Op() { fulfill in
            // cancel immediately
            let cts = CancellationTokenSource()
            cts.cancel()
            queue.execute(token: cts.token) {
                sleep(UInt32(Double(rnd(10)) / 100.0))
                XCTFail() // must not be executed
                $0()
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

