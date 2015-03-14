//
//  ImageManagerTest.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 3/14/15.
//  Copyright (c) 2015 Alexander Grebenyuk. All rights reserved.
//

import XCTest
import Nuke

class ImageManagerTest: XCTestCase {
    var manager: ImageManager!
    
    override func setUp() {
        super.setUp()

        manager = ImageManager()
    }
    
    override func tearDown() {
        super.tearDown()
    }

    func testExample() {
        let expecation = self.expectationWithDescription("Expectation")
        let request = ImageRequest(URL: NSURL(string: "https://raw.githubusercontent.com/kean/DFImageManager/master/DFImageManager/Tests/Resources/Image.jpg")!)
        let task = self.manager.imageTaskWithRequest(request) { (response) -> Void in
            expecation.fulfill()
        }
        task.resume()
        self.waitForExpectationsWithTimeout(20.0, handler: nil)
    }
}
