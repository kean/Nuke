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

// MARK: - ImageTask

extension ImageTask {
    /// Waits until the given number of streams created for the task are
    /// registered with the pipeline, which happens asynchronously.
    @ImagePipelineActor func waitUntilObserved(count: Int = 1) async {
        while _observers.count < count {
            await Task.yield()
        }
    }
}

extension ImagePipeline {
    /// Starts a task for the given request and records every progress update
    /// that it reports.
    ///
    /// Data loading stays suspended until the recording stream is registered
    /// with the pipeline, which happens asynchronously: a stream created after
    /// the download starts misses the updates that preceded it.
    ///
    /// The updates are read from `events`, which buffers all of them, and not
    /// from `progress`, which keeps only the most recent one when the consumer
    /// can't keep up with the download.
    func recordProgress(for request: ImageRequest) async -> (task: ImageTask, progress: [ImageTask.Progress]) {
        let queue = configuration.dataLoadingQueue
        queue.isSuspended = true
        let task = imageTask(with: request)
        async let progress = task.events.reduce(into: [ImageTask.Progress]()) { values, event in
            if case .progress(let value) = event {
                values.append(value)
            }
        }
        await task.waitUntilObserved()
        queue.isSuspended = false
        return (task, await progress)
    }
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
