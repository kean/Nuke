// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#warning("TODO: reimplement")
//
//class DataLoaderTests: XCTestCase {
//    var sut: DataLoader!
//    private let observer = MockDataLoaderObserver()
//
//    override func setUp() {
//        super.setUp()
//
//        sut = DataLoader()
//    }
//
//    var url: URL {
//        Test.url(forResource: "fixture", extension: "jpeg")
//    }
//
//    var request: ImageRequest {
//        ImageRequest(url: url)
//    }
//
//    // MARK: - Loading
//
//    func testDataIsLoaded() {
//        // WHEN
//        var recordedData = Data()
//        var recorededResponse: URLResponse?
//        let expectation = self.expectation(description: "DataLoaded")
//        _ = sut.loadData(with: URLRequest(url: url), didReceiveData: { data, response in
//            recordedData.append(data)
//            recorededResponse = response
//        }, completion: { error in
//            XCTAssertNil(error)
//            expectation.fulfill()
//        })
//        wait()
//
//        // THEN
//        XCTAssertEqual(recordedData.count, 22789)
//        XCTAssertEqual(recorededResponse?.url, url)
//    }
//
//    // MARK: - DataLoaderObserving
//
//    func testDataLoaderObserving() {
//        // GIVEN
//        sut.observer = observer
//
//        // WHEN
//        let expectation = self.expectation(description: "DataLoaded")
//        _ = sut.loadData(with: URLRequest(url: url), didReceiveData: { _, _ in }, completion: { _ in
//            expectation.fulfill()
//        })
//        wait()
//
//        // THEN
//        XCTAssertEqual(observer.recorededEvents.count, 4)
//        XCTAssertEqual(observer.recorededMetrics.count, 1)
//    }
//}
//
//private final class MockDataLoaderObserver: DataLoaderObserving {
//    var recorededEvents: [DataTaskEvent] = []
//    var recorededMetrics: [URLSessionTaskMetrics] = []
//
//    func dataLoader(_ loader: DataLoader, urlSession: URLSession, dataTask: URLSessionDataTask, didReceiveEvent event: DataTaskEvent) {
//        recorededEvents.append(event)
//    }
//
//    func dataLoader(_ loader: DataLoader, urlSession: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
//        recorededMetrics.append(metrics)
//    }
//}
