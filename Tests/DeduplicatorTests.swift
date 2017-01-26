// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class DeduplicatorTests: XCTestCase {
    var deduplicator: Deduplicator!
    var loader: MockImageLoader!
    
    override func setUp() {
        super.setUp()
        
        loader = MockImageLoader()
        deduplicator = Deduplicator(loader: loader)
    }
    
    func testThatEquivalentRequestsAreDeduplicated() {
        loader.queue.isSuspended = true
        
        let request1 = Request(url: defaultURL)
        let request2 = Request(url: defaultURL)
        XCTAssertTrue(Request.loadKey(for: request1) == Request.loadKey(for: request2))

        expect { fulfill in
            deduplicator.loadImage(with: request1) {
                XCTAssertNotNil($0.value)
                fulfill()
            }
        }

        expect { fulfill in
            deduplicator.loadImage(with: request2) {
                XCTAssertNotNil($0.value)
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
            deduplicator.loadImage(with: request1) {
                XCTAssertNotNil($0.value)
                fulfill()
            }
        }
        
        expect { fulfill in
            deduplicator.loadImage(with: request2) {
                XCTAssertNotNil($0.value)
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
        
        // We expect completion to get called, since it going to be "retained" by
        // other request.
        expect { fulfill in
            deduplicator.loadImage(with: Request(url: defaultURL), token: cts.token) {
                XCTAssertNotNil($0.value)
                fulfill()
            }
        }
        
        expect { fulfill in // This work we don't cancel
            deduplicator.loadImage(with: Request(url: defaultURL), token: nil) {
                XCTAssertNotNil($0.value)
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
