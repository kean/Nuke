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
    _ body: @Sendable () -> T
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

extension ImageTask {
    /// Returns ``ImageTask/previews``, waiting until the subscription is
    /// registered on the pipeline actor.
    ///
    /// Subscribing reaches the actor asynchronously, and unlike the terminal
    /// event, the previews produced before it lands are not replayed. A test
    /// that serves the next chunk of data only when it receives a preview
    /// deadlocks if it loses the first one, so it has to hold the data back
    /// until the subscription exists.
    func subscribedPreviews() async -> AsyncCompactMapSequence<AsyncStream<Event>, ImageResponse> {
        let previews = self.previews
        // Accessing `previews` schedules the registration on the pipeline
        // actor, so this hop normally lands after it. Don't spin waiting for
        // the exception: a busy-wait would starve the very actor it is
        // waiting for, and the rest of the suite with it.
        await Task { @ImagePipelineActor in }.value
        while await _streamContinuations.isEmpty {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return previews
    }
}
