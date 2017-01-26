// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class CancellationTokenTests: XCTestCase {
    func testCancellation() {
        let cts = CancellationTokenSource()
        let token1 = cts.token
        let token2 = cts.token
        
        XCTAssertFalse(cts.isCancelling)
        XCTAssertFalse(token1.isCancelling)
        XCTAssertFalse(token2.isCancelling)
        XCTAssertFalse(cts.token.isCancelling)
        
        cts.cancel()
        
        XCTAssertTrue(cts.isCancelling)
        XCTAssertTrue(token1.isCancelling)
        XCTAssertTrue(token2.isCancelling)
        XCTAssertTrue(cts.token.isCancelling)
    }
    
    func testThatTheRegisteredClosureIsCalled() {
        let cts = CancellationTokenSource()
        
        expect { fulfill in
            cts.token.register {
                fulfill()
            }
        }
        
        cts.cancel()
        
        wait()
    }
    
    func testThatTheRegisteredClosureIsCalledWhenRegisteringAfterCancellation() {
        let cts = CancellationTokenSource()
        
        cts.cancel()
        
        var isClosureCalled = false
        cts.token.register {
            isClosureCalled = true
        }
        
        XCTAssertTrue(isClosureCalled)
    }
    
    func testThreadSafety() {
        for _ in 0..<100 {
            let cts = CancellationTokenSource()
            
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
        
        wait(10)
    }
}
