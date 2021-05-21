// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
import Foundation
@testable import Nuke

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

#if os(watchOS)
import WatchKit
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
    func toLoadImage(with request: ImageRequestConvertible, completion: @escaping ((Result<ImageResponse, ImagePipeline.Error>) -> Void)) -> TestRecordedImageRequest {
        toLoadImage(with: request, progress: nil, completion: completion)
    }

    @discardableResult
    func toLoadImage(with request: ImageRequestConvertible,
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
    func toLoadData(with request: ImageRequestConvertible) -> TestRecorededDataTask {
        let record = TestRecorededDataTask()
        let request = request.asImageRequest()
        let expectation = test.expectation(description: "Data loaded for \(request)")
        record._task = pipeline.loadData(with: request, progress: nil) { result in
            XCTAssertTrue(Thread.isMainThread)
            record.result = result
            expectation.fulfill()
        }
        return record
    }
}

extension XCTestCase {
    func expectToFinishLoadingImage(with request: ImageRequest,
                                    options: ImageLoadingOptions = ImageLoadingOptions.shared,
                                    into imageView: ImageDisplayingView,
                                    completion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil) {
        let expectation = self.expectation(description: "Image loaded for \(request)")
        Nuke.loadImage(
            with: request,
            options: options,
            into: imageView,
            completion: { result in
                XCTAssertTrue(Thread.isMainThread)
                completion?(result)
                expectation.fulfill()
        })
    }

    func expectToLoadImage(with request: ImageRequest, options: ImageLoadingOptions = ImageLoadingOptions.shared, into imageView: ImageDisplayingView) {
        expectToFinishLoadingImage(with: request, options: options, into: imageView) { result in
            XCTAssertTrue(result.isSuccess)
        }
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
