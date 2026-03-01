// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import CoreGraphics
@testable import Nuke

/// Suspends data loading, executes the body to register pipeline tasks,
/// waits for all tasks to start, then resumes data loading.
@discardableResult
func withSuspendedDataLoading<T>(
    for pipeline: ImagePipeline,
    expectedCount: Int,
    _ body: () -> T
) async -> T {
    let dataLoader = pipeline.configuration.dataLoader as! MockDataLoader
    dataLoader.isSuspended = true
    let expectation = TestExpectation()
    var count = 0
    let lock = NSLock()
    pipeline.onTaskStarted = { _ in
        lock.lock()
        count += 1
        let done = count == expectedCount
        lock.unlock()
        if done { expectation.fulfill() }
    }
    let result = body()
    await expectation.wait()
    pipeline.onTaskStarted = nil
    dataLoader.isSuspended = false
    return result
}

// MARK: - Image Comparison

func isEqualImages(_ lhs: PlatformImage, _ rhs: PlatformImage) -> Bool {
    guard lhs.sizeInPixels == rhs.sizeInPixels else {
        return false
    }
    guard let lhsData = bitmapData(for: lhs),
          let rhsData = bitmapData(for: rhs) else {
        return false
    }
    return lhsData == rhsData
}

private func bitmapData(for image: PlatformImage) -> Data? {
    guard let cgImage = image.cgImage else { return nil }
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerRow = width * 4
    var data = Data(count: height * bytesPerRow)
    guard let context = data.withUnsafeMutableBytes({ ptr -> CGContext? in
        CGContext(
            data: ptr.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }) else { return nil }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return data
}
