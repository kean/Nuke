// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ManagerTests: XCTestCase {
    var view: ImageView!
    var loader: MockImageLoader!
    var manager: Manager!
    
    override func setUp() {
        super.setUp()
        
        view = ImageView()
        loader = MockImageLoader()
        manager = Manager(loader: loader)
    }

    func testThatImageIsLoaded() {
        expect { fulfill in
            manager.loadImage(with: Request(url: defaultURL), into: view) {
                if case .fulfilled(_) = $0 {
                    fulfill()
                }
                XCTAssertFalse($1)
            }
        }
        wait()
    }

    func testThatImageLoadedIntoTarget() {
        expect { fulfill in
            let target = MockTarget()
            target.handler = { resolution, isFromMemoryCache in
                if case .fulfilled(_) = resolution {
                    fulfill()
                }
                XCTAssertFalse(isFromMemoryCache)
                
                // capture target in a closure
                target.handler = nil
            }
            
            manager.loadImage(with: defaultURL, into: target)
        }
        wait()
    }
    
    func testThatPreviousTaskIsCancelledWhenNewOneIsCreated() {
        expect { fulfill in
            manager.loadImage(with: Request(url: URL(string: "http://test.com/1")!), into: view) {
                // we don't expect this to be called
                if case .fulfilled(_) = $0.0 {
                    fulfill()
                }
            }
            
            manager.loadImage(with: Request(url: URL(string: "http://test.com/2")!), into: view) {
                if case .fulfilled(_) = $0.0 {
                    fulfill()
                }
            }
        }
        
        wait()
    }
}
