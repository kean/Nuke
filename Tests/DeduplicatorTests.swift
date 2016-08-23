// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class DeduplicatorTests: XCTestCase {
    var deduplicator: Deduplicator!
    var loader: MockImageLoader!
    
    override func setUp() {
        super.setUp()
        
        loader = MockImageLoader()
        deduplicator = Deduplicator(with: loader)
    }
    
    func testThatEquivalentRequestsAreDeduplicated() {
        loader.queue.isSuspended = true
        
        let request1 = Request(url: defaultURL)
        let request2 = Request(url: defaultURL)
        XCTAssertTrue(Request.loadKey(for: request1) == Request.loadKey(for: request2))

        expect { fulfill in
            _ = deduplicator.loadImage(with: request1).then { _ in
                fulfill()
            }
        }

        expect { fulfill in
            _ = deduplicator.loadImage(with: request2).then { _ in
                fulfill()
            }
        }

        loader.queue.isSuspended = false
        
        wait { _ in
            XCTAssertEqual(self.loader.createdTaskCount, 1)
        }
    }
    
    func testThatNonEquivalentRequestsAreNotDeduplicated() {
        let request1 = Request(urlRequest: URLRequest(url: defaultURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        let request2 = Request(urlRequest: URLRequest(url: defaultURL, cachePolicy: .returnCacheDataDontLoad, timeoutInterval: 0))
        XCTAssertFalse(Request.loadKey(for: request1) == Request.loadKey(for: request2))
                
        expect { fulfill in
            _ = deduplicator.loadImage(with: request1).then { _ in
                fulfill()
            }
        }
        
        expect { fulfill in
            _ = deduplicator.loadImage(with: request2).then { _ in
                fulfill()
            }
        }
        
        wait { _ in
            XCTAssertEqual(self.loader.createdTaskCount, 2)
        }
    }
    
    func testThatDeduplicatedRequestIsNotCancelledAfterSingleUnsubsribe() {
        loader.queue.isSuspended = true
        
        // We test it using Manager because Loader is not required
        // to call completion handler for cancelled requests.
        let cts = CancellationTokenSource()
        
        // We expect promise to resolve, since it going to be "retained" by
        // other request.
        expect { fulfill in
            _ = deduplicator.loadImage(with: defaultURL, token: cts.token).then { _ in
                fulfill()
            }
        }
        
        expect { fulfill in // This work we don't cancel
            _ = deduplicator.loadImage(with: defaultURL, token: nil).then { _ in
                fulfill()
            }
        }

        cts.cancel()
        self.loader.queue.isSuspended = false

        wait { _ in
            XCTAssertEqual(self.loader.createdTaskCount, 1)
        }
    }

    func testThreadSafety() {
        runThreadSafetyTests(for: deduplicator)
    }
}
