// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ViewExtensionsTests: XCTestCase {
    var view: ImageView!
    var loader: MockImageLoader!
    
    override func setUp() {
        super.setUp()
        
        view = ImageView()
        loader = MockImageLoader()
        
        view.nk_context.loader = loader
        view.nk_context.cache = nil
    }

    func testThatImageIsLoaded() {
        expect { fulfill in
            view.nk_context.handler = { response, _ in
                XCTAssertNotNil(response.value)
                fulfill()
            }
        }
        view.nk_setImage(with: defaultURL)
        wait()
    }

    func testThatPreviousTaskIsCancelledWhenNewOneIsCreated() {
        expect { fulfill in
            view.nk_context.handler = { response, _ in
                XCTAssertTrue(response.isSuccess)
                fulfill() // should be called just once
            }
        }

        view.nk_setImage(with: URL(string: "http://test.com/1")!)
        view.nk_setImage(with: URL(string: "http://test.com/2")!)
        
        wait()
    }
    
    func testThatTaskGetsCancellonOnViewDeallocation() {
        _ = expectNotification(MockImageLoader.DidCancelTask)
        view.nk_setImage(with: defaultURL)
        view = nil
        wait()
    }
}
