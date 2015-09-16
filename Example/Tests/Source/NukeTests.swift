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
    func testExample() {
        let configuration = ImageManagerConfiguration(dataLoader: ImageDataLoader(), cache: ImageMemoryCache(), processor: ImageProcessor())
        let manager = ImageManager(configuration: configuration)
        let request = ImageRequest(URL: NSURL(string: "https://cloud.githubusercontent.com/assets/1567433/9781832/0719dd5e-57a1-11e5-9324-9764de25ed47.jpg")!)
        let expectation = self.expectationWithDescription("Desc")
        let task = manager.imageTaskWithRequest(request) {
            (response: ImageResponse) -> Void in
            XCTAssertNotNil(response, "")
            expectation.fulfill()
        }
        task.resume()
        self.waitForExpectationsWithTimeout(10.0, handler: nil)
    }
}
