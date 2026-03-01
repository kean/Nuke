// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import XCTest
import Foundation
import Nuke

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
#endif

#if os(macOS)
import Cocoa
#endif

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
