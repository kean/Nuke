// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ImageProcessingPerformanceTests: XCTestCase {
    func testCreatingProcessorIdentifiers() {
        let decompressor = ImageProcessors.Resize(size: CGSize(width: 1, height: 1), contentMode: .aspectFill, upscale: false)

        measure {
            for _ in 0..<25_000 {
                _ = decompressor.identifier
            }
        }
    }

    func testComparingTwoProcessorCompositions() {

        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "123"), ImageProcessors.Resize(size: CGSize(width: 1, height: 1), contentMode: .aspectFill, upscale: false)])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "124"), ImageProcessors.Resize(size: CGSize(width: 1, height: 1), contentMode: .aspectFill, upscale: false)])

        measure {
            for _ in 0..<25_000 {
                if lhs.hashableIdentifier == rhs.hashableIdentifier {
                    // do nothing
                }
            }
        }
    }

    func testImageDecoding() {
        let decoder = ImageDecoders.Default()

        let data = Test.data
        measure {
            for _ in 0..<1_000 {
                let _ = decoder.decode(data)
            }
        }
    }
}
