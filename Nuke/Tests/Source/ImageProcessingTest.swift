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
        
        self.mockSessionManager = MockImageDataLoader()
        let loaderConfiguration = ImageLoaderConfiguration(dataLoader: self.mockSessionManager)
        self.manager = ImageManager(configuration: ImageManagerConfiguration(loader: ImageLoader(configuration: loaderConfiguration), cache: self.mockMemoryCache))
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: Applying Filters

    func testThatImageIsProcessed() {
        var request = ImageRequest(URL: defaultURL)
        request.processor = MockImageProcessor(ID: "processor1")

        self.expect { fulfill in
            self.manager.taskWith(request) {
                XCTAssertEqual($0.image!.nk_test_processorIDs, ["processor1"])
                fulfill()
            }.resume()
        }
        self.wait()
    }

    func testThatProcessedImageIsMemCached() {
        self.expect { fulfill in
            var request = ImageRequest(URL: defaultURL)
            request.processor = MockImageProcessor(ID: "processor1")

            self.manager.taskWith(request) {
                XCTAssertNotNil($0.image)
                fulfill()
            }.resume()
        }
        self.wait()

        var request = ImageRequest(URL: defaultURL)
        request.processor = MockImageProcessor(ID: "processor1")
        guard let image = self.manager.responseForRequest(request)?.image else {
            XCTFail()
            return
        }
        XCTAssertEqual(image.nk_test_processorIDs, ["processor1"])
    }

    func testThatCorrectFiltersAreAppiedWhenDataTaskIsReusedForMultipleRequests() {
        var request1 = ImageRequest(URL: defaultURL)
        request1.processor = MockImageProcessor(ID: "processor1")

        var request2 = ImageRequest(URL: defaultURL)
        request2.processor = MockImageProcessor(ID: "processor2")

        self.expect { fulfill in
            self.manager.taskWith(request1) {
                XCTAssertEqual($0.image!.nk_test_processorIDs, ["processor1"])
                fulfill()
            }.resume()
        }

        self.expect { fulfill in
            self.manager.taskWith(request2) {
                XCTAssertEqual($0.image!.nk_test_processorIDs, ["processor2"])
                fulfill()
            }.resume()
        }

        self.wait { _ in
            XCTAssertEqual(self.mockSessionManager.createdTaskCount, 1)
        }
    }

    // MARK: Composing Filters

    func testThatImageIsProcessedWithFilterComposition() {
        var request = ImageRequest(URL: defaultURL)
        request.processor = ImageProcessorComposition(processors: [MockImageProcessor(ID: "processor1"), MockImageProcessor(ID: "processor2")])

        self.expect { fulfill in
            self.manager.taskWith(request) {
                XCTAssertEqual($0.image!.nk_test_processorIDs, ["processor1", "processor2"])
                fulfill()
                }.resume()
        }
        self.wait()
    }

    func testThatImageProcessedWithFilterCompositionIsMemCached() {
        self.expect { fulfill in
            var request = ImageRequest(URL: defaultURL)
            request.processor = ImageProcessorComposition(processors: [MockImageProcessor(ID: "processor1"), MockImageProcessor(ID: "processor2")])
            self.manager.taskWith(request) {
                XCTAssertNotNil($0.image)
                fulfill()
            }.resume()
        }
        self.wait()

        var request = ImageRequest(URL: defaultURL)
        request.processor = ImageProcessorComposition(processors: [MockImageProcessor(ID: "processor1"), MockImageProcessor(ID: "processor2")])
        guard let image = self.manager.responseForRequest(request)?.image else {
            XCTFail()
            return
        }
        XCTAssertEqual(image.nk_test_processorIDs, ["processor1", "processor2"])
    }
    
    func testThatImageFilterWorksWithHeterogeneousFilters() {
        let composition1 = ImageProcessorComposition(processors: [MockImageProcessor(ID: "ID1"), MockParameterlessImageProcessor()])
        let composition2 = ImageProcessorComposition(processors: [MockImageProcessor(ID: "ID1"), MockParameterlessImageProcessor()])
        let composition3 = ImageProcessorComposition(processors: [MockParameterlessImageProcessor(), MockImageProcessor(ID: "ID1")])
        let composition4 = ImageProcessorComposition(processors: [MockParameterlessImageProcessor(), MockImageProcessor(ID: "ID1"), MockImageProcessor(ID: "ID2")])
        XCTAssertEqual(composition1, composition2)
        XCTAssertNotEqual(composition1, composition3)
        XCTAssertNotEqual(composition1, composition4)
    }
}
