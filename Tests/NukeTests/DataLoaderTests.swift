// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(watchOS) && !os(tvOS)

class DataLoaderTests: XCTestCase {
    var sut: DataLoader!
    private let delegate = MockSessionDelegate()

    override func setUp() {
        super.setUp()

        sut = DataLoader()
    }

    var url: URL {
        Test.url(forResource: "fixture", extension: "jpeg")
    }

    var request: ImageRequest {
        ImageRequest(url: url)
    }

    // MARK: - Loading

    func testDataIsLoaded() {
        // WHEN
        var recordedData = Data()
        var recorededResponse: URLResponse?
        let expectation = self.expectation(description: "DataLoaded")
        _ = sut.loadData(with: URLRequest(url: url), didReceiveData: { data, response in
            recordedData.append(data)
            recorededResponse = response
        }, completion: { error in
            XCTAssertNil(error)
            expectation.fulfill()
        })
        wait()

        // THEN
        XCTAssertEqual(recordedData.count, 22789)
        XCTAssertEqual(recorededResponse?.url, url)
    }

    // MARK: - Custom Delegate

    func testCustomDelegate() {
        // GIVEN
        sut.delegate = delegate

        // WHEN
        let expectation = self.expectation(description: "DataLoaded")
        _ = sut.loadData(with: URLRequest(url: url), didReceiveData: { _, _ in }, completion: { _ in
            DispatchQueue.main.async {
                expectation.fulfill()
            }
        })
        wait(for: [expectation], timeout: 2.0)

        // THEN
        XCTAssertEqual(delegate.recordedMetrics.count, 1)
    }
}

private final class MockSessionDelegate: NSObject, URLSessionTaskDelegate {
    var recordedMetrics: [URLSessionTaskMetrics] = []

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        recordedMetrics.append(metrics)
    }
}

#endif
