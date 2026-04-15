// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif
@testable import Nuke
@testable import NukeExtensions

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@Suite(.timeLimit(.minutes(5))) @MainActor
struct ImageViewIntegrationTests {
    let imageView: _ImageView
    let pipeline: ImagePipeline
    let options: ImageLoadingOptions

    init() {
        self.pipeline = ImagePipeline {
            $0.dataLoader = DataLoader()
            $0.imageCache = MockImageCache()
        }
        self.imageView = _ImageView()
        var options = ImageLoadingOptions()
        options.pipeline = pipeline
        self.options = options
    }

    var url: URL {
        Test.url(forResource: "fixture", extension: "jpeg")
    }

    var request: ImageRequest {
        ImageRequest(url: url)
    }

    // MARK: - Loading

    @Test func imageLoaded() async {
        await loadImageExpectingSuccess(with: request, options: options, into: imageView)
        #expect(imageView.image != nil)
    }

    @Test func imageLoadedWithURL() async {
        let expectation = TestExpectation()
        NukeExtensions.loadImage(with: url, options: options, into: imageView) { _ in
            expectation.fulfill()
        }
        await expectation.wait()
        #expect(imageView.image != nil)
    }

    // MARK: - Loading with Invalid URL

    @Test func loadImageWithInvalidURLString() async {
        let expectation = TestExpectation()
        NukeExtensions.loadImage(with: URL(string: ""), options: options, into: imageView) { result in
            #expect(result.error == .imageRequestMissing)
            expectation.fulfill()
        }
        await expectation.wait()
        #expect(imageView.image == nil)
    }

    @Test func loadingWithNilURL() async {
        // GIVEN
        var urlRequest = URLRequest(url: Test.url)
        urlRequest.url = nil // Not sure why this is even possible

        // WHEN
        let expectation = TestExpectation()
        NukeExtensions.loadImage(with: ImageRequest(urlRequest: urlRequest), options: options, into: imageView) { result in
            // THEN
            #expect(result.error?.dataLoadingError != nil)
            expectation.fulfill()
        }
        await expectation.wait()
        #expect(imageView.image == nil)
    }

    @Test func loadingWithRequestWithNilURL() async {
        // GIVEN
        let input = ImageRequest(url: nil)

        // WHEN/THEN
        let expectation = TestExpectation()
        pipeline.loadImage(with: input) {
            #expect($0.isFailure)
            expectation.fulfill()
        }
        await expectation.wait()
    }

    // MARK: - Data Passed

#if os(iOS) || os(visionOS)
    private final class MockView: UIView, Nuke_ImageDisplaying {
        func nuke_display(image: PlatformImage?, data: Data?) {
            recordedData.append(data)
        }

        var recordedData = [Data?]()
    }

    // Disabled test
    func _testThatAttachedDataIsPassed() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in
                ImageDecoders.Empty()
            }
        }

        let imageView = MockView()

        var options = ImageLoadingOptions()
        options.pipeline = pipeline
        options.isPrepareForReuseEnabled = false

        // WHEN
        let expectation = TestExpectation()
        NukeExtensions.loadImage(with: Test.url, options: options, into: imageView) { result in
            #expect(result.value != nil)
            #expect(result.value?.container.data != nil)
            expectation.fulfill()
        }
        await expectation.wait()

        // THEN
        let data = try #require(imageView.recordedData.first)
        #expect(data != nil)
    }

#endif
}

#endif
