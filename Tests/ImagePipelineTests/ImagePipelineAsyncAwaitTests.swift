// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if swift(>=5.5.2)
@available(iOS 13.0, tvOS 13.0, macOS 10.15, watchOS 6.0, *)
class ImagePipelineAsyncAwaitTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }
}

/// We have to mock it because there is no way to construct native `URLError`
/// with a `networkUnavailableReason`.
private struct URLError: Swift.Error {
    var networkUnavailableReason: NetworkUnavailableReason?

    enum NetworkUnavailableReason {
        case cellular
        case expensive
        case constrained
    }
}
#endif
