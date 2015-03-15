//
//  NukeTests.swift
//  NukeTests
//
//  Created by Alexander Grebenyuk on 3/12/15.
//  Copyright (c) 2015 Alexander Grebenyuk. All rights reserved.
//

import Nuke
import UIKit
import XCTest

class NukeTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        let manager = ImageManager(sessionManager: URLSessionManager())
        let request = ImageRequest(URL: NSURL(string: "https://raw.githubusercontent.com/kean/DFImageManager/master/DFImageManager/Tests/Resources/Image.jpg")!)
        let expectation = self.expectationWithDescription("Desc")
        let task = manager.imageTaskWithRequest(request) { (response) -> Void in
            expectation.fulfill()
        }.resume()
        self.waitForExpectationsWithTimeout(10.0, handler: nil)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock() {
            // Put the code you want to measure the time of here.
        }
    }
    
}
