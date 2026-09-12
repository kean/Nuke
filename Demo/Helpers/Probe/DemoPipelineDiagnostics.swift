// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// What a pipeline has done since the last reset: a copy of the figures
/// ``DemoPipelineProbe`` counts, for one pipeline or added up over all of them.
///
/// It is shaped like `AnimatedImagePlayer.Diagnostics` and read the same way:
/// sampled on a timer rather than observed. Every figure is stored rather than
/// computed on the way out, so a snapshot costs a lock and a copy. Work that
/// was running when the probe was reset is counted when it ends.
///
/// The probe sees a pipeline only through its delegate, so each figure says
/// where it is counted and what that misses. What none of them can see is
/// listed at the top of `DemoPipelineProbe.swift`.
struct DemoPipelineDiagnostics: Sendable {
    /// The label the pipeline was created with, or "All pipelines" for a total.
    var label = ""
    /// The number of pipelines the figures add up.
    var pipelineCount = 0

    // MARK: Tasks

    /// The image tasks created, counted in `imageTaskCreated`. Includes the
    /// tasks of an `ImagePrefetcher` that fills the memory cache.
    ///
    /// Doesn't include `data(for:)` or a prefetcher that fills the disk cache,
    /// which run data tasks the delegate never hears of, or NukeUI's memory
    /// cache hits, which create no task.
    var createdTaskCount = 0
    /// The tasks created and not yet finished.
    var activeTaskCount = 0
    /// The most tasks active at once. In a total, the highest of the pipelines'
    /// peaks, which is a floor under the peak they reached together.
    var peakActiveTaskCount = 0
    /// The tasks that finished with an image.
    var succeededTaskCount = 0
    /// The tasks that finished cancelled, including the ones cancelled before
    /// the pipeline started them.
    var cancelledTaskCount = 0
    /// The tasks that failed with any error other than a cancellation.
    var failedTaskCount = 0
    /// ``failedTaskCount`` by `ImagePipeline.Error` case, such as
    /// `"dataLoadingFailed"`.
    var failureCounts: [String: Int] = [:]
    /// From `imageTaskCreated` to the `.finished` event, for the tasks that
    /// succeeded. It includes the hop to the pipeline's actor that delivers
    /// the event.
    var taskDuration = Timing()

    // MARK: Sources

    /// The tasks whose image came from the memory cache: `.finished` with a
    /// `cacheType` of `.memory`.
    var memoryResponseCount = 0
    /// The tasks whose image was decoded from the disk cache (`DataCaching`):
    /// `.finished` with a `cacheType` of `.disk`.
    var diskResponseCount = 0
    /// The tasks whose image came from a download: `.finished` with no
    /// `cacheType`. That includes a download `URLCache` answered, which a task
    /// can't tell apart.
    var networkResponseCount = 0

    // MARK: Disk Cache

    /// The writes to the disk cache, counted when `willCache` lets one through.
    /// A direct `pipeline.cache.storeCachedData` doesn't go through `willCache`
    /// and isn't counted.
    var diskWriteCount = 0
    /// The bytes those writes stored.
    var diskWriteByteCount: Int64 = 0
    /// The writes that stored an encoded image rather than the original data,
    /// as `DataCachePolicy` decides.
    var encodedImageWriteCount = 0

    // MARK: Downloads

    /// The downloads the pipeline started: one `dataLoader(for:)` per download,
    /// after coalescing. Local files and `ImageRequest(id:data:)` don't load.
    var downloadCount = 0

    // MARK: Decompression

    /// The calls to `decompress`: the time it took to prepare the bitmap for
    /// display. The pipeline asks only for final images that aren't thumbnails
    /// or processed, for requests without `.skipDecompression`.
    var decompression = Timing()
    /// The times `shouldDecompress` said no. The pipeline's own reasons to skip
    /// – a thumbnail, a processed image, `.skipDecompression` – are decided
    /// before it asks and aren't counted.
    var declinedDecompressionCount = 0

    // MARK: Queues

    /// The data loading queue. The delegate hears a download start but not
    /// end, so `inFlightCount` is `nil`.
    var dataLoadingQueue = Queue(inFlightCount: nil)
    /// The decoding queue. The delegate doesn't see a decode run, so
    /// `inFlightCount` is `nil`.
    var decodingQueue = Queue(inFlightCount: nil)
    /// Processors come with the request, not from the delegate, so nothing
    /// counts them: `inFlightCount` is always `nil`.
    var processingQueue = Queue(inFlightCount: nil)
    /// The calls to `decompress` running.
    var decompressingQueue = Queue(inFlightCount: 0)
    /// The encoding queue. The delegate doesn't see an encode run, so
    /// `inFlightCount` is `nil`.
    var encodingQueue = Queue(inFlightCount: nil)

    // MARK: Derived

    /// The share of the tasks whose image didn't need a download, from 0 to 1.
    /// NukeUI's memory cache hits create no task and aren't in it.
    var hitRate: Double {
        let hits = memoryResponseCount + diskResponseCount
        let total = hits + networkResponseCount
        return total > 0 ? Double(hits) / Double(total) : 0
    }
}

extension DemoPipelineDiagnostics {
    /// How long one kind of work took, in seconds.
    struct Timing: Sendable {
        /// The number of times the work was measured.
        var count = 0
        /// The time they took together.
        var total: TimeInterval = 0
        /// The most recent one.
        var last: TimeInterval = 0
        /// The slowest one.
        var max: TimeInterval = 0
        /// When ``last`` was measured, so a total can take the latest of its
        /// pipelines' figures.
        var lastMeasuredAt: ContinuousClock.Instant?

        /// The mean.
        var average: TimeInterval {
            count > 0 ? total / Double(count) : 0
        }

        mutating func record(_ duration: TimeInterval, at instant: ContinuousClock.Instant) {
            count += 1
            total += duration
            last = duration
            max = Swift.max(max, duration)
            lastMeasuredAt = instant
        }

        mutating func add(_ other: Timing) {
            count += other.count
            total += other.total
            max = Swift.max(max, other.max)
            if let instant = other.lastMeasuredAt, lastMeasuredAt.map({ $0 < instant }) ?? true {
                last = other.last
                lastMeasuredAt = instant
            }
        }
    }

    /// One of the pipeline's task queues.
    struct Queue: Sendable {
        /// The work of the queue's kind running now, counted by the probe on
        /// the way in and out. It isn't the queue's own count: that one is
        /// internal, and so is the number of operations waiting. `nil` where
        /// the probe can't see the work.
        var inFlightCount: Int?
        /// `maxConcurrentTaskCount`. In a total, the limits of the distinct
        /// queues added up.
        var limit = 0
        /// `isSuspended`. In a total, `true` if any of the queues is.
        var isSuspended = false

        mutating func add(_ other: Queue, isDistinctQueue: Bool) {
            if let count = other.inFlightCount {
                inFlightCount = (inFlightCount ?? 0) + count
            }
            if isDistinctQueue {
                limit += other.limit
                isSuspended = isSuspended || other.isSuspended
            }
        }
    }
}

extension DemoPipelineDiagnostics {
    /// Adds the figures of another pipeline, leaving out the label and the
    /// queues, which a total puts together on its own.
    mutating func add(_ other: DemoPipelineDiagnostics) {
        pipelineCount += other.pipelineCount

        createdTaskCount += other.createdTaskCount
        activeTaskCount += other.activeTaskCount
        peakActiveTaskCount = max(peakActiveTaskCount, other.peakActiveTaskCount)
        succeededTaskCount += other.succeededTaskCount
        cancelledTaskCount += other.cancelledTaskCount
        failedTaskCount += other.failedTaskCount
        failureCounts.merge(other.failureCounts, uniquingKeysWith: +)
        taskDuration.add(other.taskDuration)

        memoryResponseCount += other.memoryResponseCount
        diskResponseCount += other.diskResponseCount
        networkResponseCount += other.networkResponseCount

        diskWriteCount += other.diskWriteCount
        diskWriteByteCount += other.diskWriteByteCount
        encodedImageWriteCount += other.encodedImageWriteCount

        downloadCount += other.downloadCount

        decompression.add(other.decompression)
        declinedDecompressionCount += other.declinedDecompressionCount
    }

    /// The figures of a pipeline that is gone: the counts it reached, with
    /// nothing left in flight.
    var retired: DemoPipelineDiagnostics {
        var figures = self
        figures.activeTaskCount = 0
        figures.dataLoadingQueue = Queue(inFlightCount: nil)
        figures.decodingQueue = Queue(inFlightCount: nil)
        figures.processingQueue = Queue(inFlightCount: nil)
        figures.decompressingQueue = Queue(inFlightCount: 0)
        figures.encodingQueue = Queue(inFlightCount: nil)
        return figures
    }
}
