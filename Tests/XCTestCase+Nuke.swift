// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
import Foundation
@testable import Nuke

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
#endif

#if os(macOS)
import Cocoa
#endif

extension XCTestCase {
    func expect(_ pipeline: ImagePipeline) -> TestExpectationImagePipeline {
        return TestExpectationImagePipeline(test: self, pipeline: pipeline)
    }
}

struct TestExpectationImagePipeline {
    let test: XCTestCase
    let pipeline: ImagePipeline

    @discardableResult
    func toLoadImage(with request: ImageRequest, completion: @escaping ((Result<ImageResponse, ImagePipeline.Error>) -> Void)) -> TestRecordedImageRequest {
        toLoadImage(with: request, progress: nil, completion: completion)
    }

    @discardableResult
    func toLoadImage(with request: ImageRequest,
                     progress: ((_ intermediateResponse: ImageResponse?, _ completedUnitCount: Int64, _ totalUnitCount: Int64) -> Void)? = nil,
                     completion: ((Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil) -> TestRecordedImageRequest {
        let record = TestRecordedImageRequest()
        let expectation = test.expectation(description: "Image loaded for \(request)")
        record._task = pipeline.loadImage(with: request, progress: progress) { result in
            completion?(result)
            record.result = result
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(result.isSuccess)
            expectation.fulfill()
        }
        return record
    }

    @discardableResult
    func toFailRequest(_ request: ImageRequest, completion: @escaping ((Result<ImageResponse, ImagePipeline.Error>) -> Void)) -> ImageTask {
        toFailRequest(request, progress: nil, completion: completion)
    }

    @discardableResult
    func toFailRequest(_ request: ImageRequest,
                       progress: ((_ intermediateResponse: ImageResponse?, _ completedUnitCount: Int64, _ totalUnitCount: Int64) -> Void)? = nil,
                       completion: ((Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil) -> ImageTask {
        let expectation = test.expectation(description: "Image request failed \(request)")
        return pipeline.loadImage(with: request, progress: progress) { result in
            completion?(result)
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(result.isFailure)
            expectation.fulfill()
        }
    }

    func toFailRequest(_ request: ImageRequest, with expectedError: ImagePipeline.Error, file: StaticString = #file, line: UInt = #line) {
        toFailRequest(request) { result in
            XCTAssertEqual(result.error, expectedError, file: file, line: line)
        }
    }

    @discardableResult
    func toLoadData(with request: ImageRequest) -> TestRecorededDataTask {
        let record = TestRecorededDataTask()
        let request = request
        let expectation = test.expectation(description: "Data loaded for \(request)")
        record._task = pipeline.loadData(with: request, progress: nil) { result in
            XCTAssertTrue(Thread.isMainThread)
            record.result = result
            expectation.fulfill()
        }
        return record
    }
}

final class TestRecordedImageRequest {
    var task: ImageTask {
        _task
    }
    fileprivate var _task: ImageTask!

    var result: Result<ImageResponse, ImagePipeline.Error>?

    var response: ImageResponse? {
        result?.value
    }

    var image: PlatformImage? {
        response?.image
    }
}

final class TestRecorededDataTask {
    var task: ImageTask {
        _task
    }
    fileprivate var _task: ImageTask!

    var result: Result<(data: Data, response: URLResponse?), ImagePipeline.Error>?

    var data: Data? {
        guard case .success(let response)? = result else {
            return nil
        }
        return response.data
    }
}

extension XCTestCase {
    func expect(_ pipeline: ImagePipeline, _ dataLoader: MockProgressiveDataLoader) -> TestExpectationProgressivePipeline {
        return TestExpectationProgressivePipeline(test: self, pipeline: pipeline, dataLoader: dataLoader)
    }
}

struct TestExpectationProgressivePipeline {
    let test: XCTestCase
    let pipeline: ImagePipeline
    let dataLoader: MockProgressiveDataLoader

    // We expect two partial images (at 5 scans, and 9 scans marks).
    func toProducePartialImages(for request: ImageRequest = Test.request,
                                withCount count: Int = 2,
                                progress: ((_ intermediateResponse: ImageResponse?, _ completedUnitCount: Int64, _ totalUnitCount: Int64) -> Void)? = nil,
                                completion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil) {
        let expectPartialImageProduced = test.expectation(description: "Partial Image Is Produced")
        expectPartialImageProduced.expectedFulfillmentCount = count

        let expectFinalImageProduced = test.expectation(description: "Final Image Is Produced")

        pipeline.loadImage(
            with: request,
            progress: { image, completed, total in
                progress?(image, completed, total)

                // This works because each new chunk resulted in a new scan
                if image != nil {
                    expectPartialImageProduced.fulfill()
                    self.dataLoader.resume()
                }
            },
            completion: { result in
                completion?(result)
                XCTAssertTrue(result.isSuccess)
                expectFinalImageProduced.fulfill()
            }
        )
    }
}

// MARK: - UIImage

func XCTAssertEqualImages(_ lhs: PlatformImage, _ rhs: PlatformImage, file: StaticString = #file, line: UInt = #line) {
    XCTAssertTrue(isEqual(lhs, rhs), "Expected images to be equal", file: file, line: line)
}

private func isEqual(_ lhs: PlatformImage, _ rhs: PlatformImage) -> Bool {
    guard lhs.sizeInPixels == rhs.sizeInPixels else {
        return false
    }
    // Note: this will probably need more work.
    let encoder = ImageEncoders.ImageIO(type: .png, compressionRatio: 1)
    return encoder.encode(lhs) == encoder.encode(rhs)
}
