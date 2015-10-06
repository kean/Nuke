//
//  ImageProcessingTest.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 06/10/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import XCTest
import Nuke

class ImageProcessingTest: XCTestCase {
    var manager: ImageManager!
    var mockMemoryCache: MockImageMemoryCache!
    var mockSessionManager: MockImageDataLoader!

    override func setUp() {
        super.setUp()

        self.mockSessionManager = MockImageDataLoader()
        self.mockMemoryCache = MockImageMemoryCache()
        self.manager = ImageManager(configuration: ImageManagerConfiguration(dataLoader: self.mockSessionManager, cache: self.mockMemoryCache))
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: Simple Filter

    func testThatImageIsProcessed() {
        var request = ImageRequest(URL: defaultURL)
        request.processor = MockImageProcessor(ID: "processor1")

        self.expect { fulfill in
            self.manager.taskWithRequest(request) {
                guard let image = $0.image as? MockProcessedImage else {
                    XCTFail()
                    return
                }
                XCTAssertEqual(image.processorIDs, ["processor1"])
                fulfill()
                }.resume()
        }
        self.wait()
    }

    func testThatProcessedImageIsMemCached() {
        self.expect { fulfill in
            var request = ImageRequest(URL: defaultURL)
            request.processor = MockImageProcessor(ID: "processor1")

            self.manager.taskWithRequest(request) {
                XCTAssertNotNil($0.image)
                fulfill()
            }.resume()
        }
        self.wait()

        var request = ImageRequest(URL: defaultURL)
        request.processor = MockImageProcessor(ID: "processor1")
        guard let image = self.manager.cachedResponseForRequest(request)?.image as? MockProcessedImage else {
            XCTFail()
            return
        }
        XCTAssertEqual(image.processorIDs, ["processor1"])
    }

    // MARK: Filter Composition

    func testThatImageIsProcessedWithFilterComposition() {
        var request = ImageRequest(URL: defaultURL)
        request.processor = ImageProcessorComposition(processors: [MockImageProcessor(ID: "processor1"), MockImageProcessor(ID: "processor2")])

        self.expect { fulfill in
            self.manager.taskWithRequest(request) {
                guard let image = $0.image as? MockProcessedImage else {
                    XCTFail()
                    return
                }
                XCTAssertEqual(image.processorIDs, ["processor1", "processor2"])
                fulfill()
                }.resume()
        }
        self.wait()
    }

    func testThatImageProcessedWithFilterCompositionIsMemCached() {
        self.expect { fulfill in
            var request = ImageRequest(URL: defaultURL)
            request.processor = ImageProcessorComposition(processors: [MockImageProcessor(ID: "processor1"), MockImageProcessor(ID: "processor2")])
            self.manager.taskWithRequest(request) {
                XCTAssertNotNil($0.image)
                fulfill()
            }.resume()
        }
        self.wait()

        var request = ImageRequest(URL: defaultURL)
        request.processor = ImageProcessorComposition(processors: [MockImageProcessor(ID: "processor1"), MockImageProcessor(ID: "processor2")])
        guard let image = self.manager.cachedResponseForRequest(request)?.image as? MockProcessedImage else {
            XCTFail()
            return
        }
        XCTAssertEqual(image.processorIDs, ["processor1", "processor2"])
    }
}
