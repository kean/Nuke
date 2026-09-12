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
/// The probe sees a pipeline only through its delegate and the decorators the
/// delegate hands it, so each figure says where it is counted and what that
/// misses. What none of them can see is listed at the top of
/// `DemoPipelineProbe.swift`.
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
    /// cache hits, which create no task (see ``memoryHitWithoutTaskCount``).
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
    /// Memory cache hits that never became a task: the synchronous lookups
    /// `LazyImage`, `LazyImageView`, and `loadImage(with:into:)` make before
    /// they start one.
    ///
    /// No delegate method hears of them, so the memory cache decorator counts
    /// the hits made on the main thread, where NukeUI looks. The pipeline's own
    /// lookups run on its actor and reach ``memoryResponseCount`` through the
    /// task that made them. Any other main-thread read of `pipeline.cache`
    /// counts here too.
    var memoryHitWithoutTaskCount = 0
    /// The tasks whose image was decoded from the disk cache (`DataCaching`):
    /// `.finished` with a `cacheType` of `.disk`.
    var diskResponseCount = 0
    /// The tasks whose image came from a download: `.finished` with no
    /// `cacheType`. That includes a download `URLCache` answered, which a task
    /// can't tell apart; see ``httpCacheLoadCount``.
    var networkResponseCount = 0

    // MARK: Memory Cache

    /// Every read of the memory cache: the pipeline's lookups, NukeUI's, and a
    /// prefetcher checking whether it has anything to do. A request NukeUI
    /// misses is looked up twice, once by the view and once by its task.
    var memoryCacheLookupCount = 0
    /// The reads that found a final image. A preview found in the cache
    /// counts as a miss, because the caller goes on to load the image.
    var memoryCacheHitCount = 0

    // MARK: Disk Cache

    /// Every read of the disk cache (`DataCaching.cachedData(for:)`). A
    /// thumbnail request that misses is read again without its thumbnail.
    var diskCacheLookupCount = 0
    /// The reads that found data.
    var diskCacheHitCount = 0
    /// The bytes those reads returned: data that didn't have to be downloaded.
    var diskCacheHitByteCount: Int64 = 0
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
    /// The downloads that completed without an error, including the ones
    /// `URLCache` answered.
    var completedDownloadCount = 0
    /// The downloads cancelled: for a `DataLoader`, when its session reports
    /// the cancellation; for any other loader, when the pipeline cancels it.
    var cancelledDownloadCount = 0
    /// The downloads that failed, including a response `DataLoader` rejected
    /// for its status code.
    var failedDownloadCount = 0
    /// The downloads in flight that were cancelled and whose loader hasn't
    /// called `completion` since.
    ///
    /// The pipeline frees a data loading slot when the loader calls
    /// `completion`, and on nothing else, so a loader that stays silent after
    /// a cancel holds its slot for good. A `DataLoader` always completes, so
    /// for one this drops back within a moment.
    var cancelledInFlightDownloadCount = 0
    /// The response bytes of the downloads that have ended, whatever their
    /// outcome, not counting the ones `URLCache` answered.
    var downloadedByteCount: Int64 = 0
    /// The response bytes received so far by the downloads still in flight.
    var inFlightByteCount: Int64 = 0
    /// From the start of a download to its first chunk of data: for a
    /// `DataLoader`, from the moment its session creates the task; for any
    /// other loader, from the call to `loadData`. Counted when the download
    /// ends, for the ones that received data and weren't answered by `URLCache`.
    var timeToFirstByte = Timing()
    /// The downloads that went over a connection an earlier request had
    /// opened. Known only for a `DataLoader`.
    var reusedConnectionCount = 0
    /// The downloads `URLCache` answered without a request. Known only for a
    /// `DataLoader`, whose session reports it.
    var httpCacheLoadCount = 0
    /// The bytes of those downloads.
    var httpCacheByteCount: Int64 = 0

    // MARK: Decoding

    /// The final decodes (`ImageDecoding.decode(_:)`) that produced an image.
    var decoding = Timing()
    /// The partial decodes that produced a preview. The attempts that had
    /// nothing new to show aren't counted.
    var previewDecoding = Timing()
    /// The final decodes that threw.
    var failedDecodeCount = 0
    /// ``decoding`` by the format of the image, such as `"jpeg"`.
    var decodingByFormat: [String: Timing] = [:]

    // MARK: Decompression

    /// The calls to `decompress`: the time it took to prepare the bitmap for
    /// display. The pipeline asks only for final images that aren't thumbnails
    /// or processed, for requests without `.skipDecompression`.
    var decompression = Timing()
    /// The times `shouldDecompress` said no. The pipeline's own reasons to skip
    /// – a thumbnail, a processed image, `.skipDecompression` – are decided
    /// before it asks and aren't counted.
    var declinedDecompressionCount = 0

    // MARK: Encoding

    /// The encodes of a processed image for the disk cache, as
    /// `DataCachePolicy` decides.
    var encoding = Timing()

    // MARK: Queues

    /// The downloads in flight, from the start of the load to `completion`.
    var dataLoadingQueue = Queue(inFlightCount: 0)
    /// The decodes running on the decoding queue: the ones whose decoder is
    /// asynchronous, which for `ImageDecoders.Default` means a thumbnail.
    /// `nil` for a pipeline recording diagnostics, whose decoders aren't wrapped.
    var decodingQueue = Queue(inFlightCount: 0)
    /// Processors come with the request, not from the delegate, so nothing
    /// counts them: `inFlightCount` is always `nil`.
    var processingQueue = Queue(inFlightCount: nil)
    /// The calls to `decompress` running.
    var decompressingQueue = Queue(inFlightCount: 0)
    /// The encodes running.
    var encodingQueue = Queue(inFlightCount: 0)

    // MARK: Derived

    /// The images served from the memory cache, with or without a task.
    var servedFromMemoryCount: Int {
        memoryResponseCount + memoryHitWithoutTaskCount
    }

    /// The share of the images that didn't need a download, from 0 to 1.
    var hitRate: Double {
        let hits = servedFromMemoryCount + diskResponseCount
        let total = hits + networkResponseCount
        return total > 0 ? Double(hits) / Double(total) : 0
    }

    /// The images each completed download produced: more than 1 when tasks
    /// that asked for the same data – with different processors, say – shared
    /// a download.
    ///
    /// Tasks served from a cache are left out, so a disk hit doesn't pass for
    /// coalescing. So are the tasks cancelled while they waited, which makes
    /// it a floor when many are.
    var coalescingRatio: Double {
        completedDownloadCount > 0 ? Double(networkResponseCount) / Double(completedDownloadCount) : 0
    }

    /// The bytes served without a request: read from the disk cache or
    /// answered by `URLCache`. A memory cache hit saves a download too, but
    /// the size of the data it saved isn't known.
    var savedByteCount: Int64 {
        diskCacheHitByteCount + httpCacheByteCount
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
        memoryHitWithoutTaskCount += other.memoryHitWithoutTaskCount
        diskResponseCount += other.diskResponseCount
        networkResponseCount += other.networkResponseCount

        memoryCacheLookupCount += other.memoryCacheLookupCount
        memoryCacheHitCount += other.memoryCacheHitCount

        diskCacheLookupCount += other.diskCacheLookupCount
        diskCacheHitCount += other.diskCacheHitCount
        diskCacheHitByteCount += other.diskCacheHitByteCount
        diskWriteCount += other.diskWriteCount
        diskWriteByteCount += other.diskWriteByteCount
        encodedImageWriteCount += other.encodedImageWriteCount

        downloadCount += other.downloadCount
        completedDownloadCount += other.completedDownloadCount
        cancelledDownloadCount += other.cancelledDownloadCount
        failedDownloadCount += other.failedDownloadCount
        cancelledInFlightDownloadCount += other.cancelledInFlightDownloadCount
        downloadedByteCount += other.downloadedByteCount
        inFlightByteCount += other.inFlightByteCount
        timeToFirstByte.add(other.timeToFirstByte)
        reusedConnectionCount += other.reusedConnectionCount
        httpCacheLoadCount += other.httpCacheLoadCount
        httpCacheByteCount += other.httpCacheByteCount

        decoding.add(other.decoding)
        previewDecoding.add(other.previewDecoding)
        failedDecodeCount += other.failedDecodeCount
        decodingByFormat.merge(other.decodingByFormat) { var timing = $0; timing.add($1); return timing }

        decompression.add(other.decompression)
        declinedDecompressionCount += other.declinedDecompressionCount

        encoding.add(other.encoding)
    }

    /// The figures of a pipeline that is gone: the counts it reached, with
    /// nothing left in flight.
    var retired: DemoPipelineDiagnostics {
        var figures = self
        figures.activeTaskCount = 0
        figures.cancelledInFlightDownloadCount = 0
        figures.inFlightByteCount = 0
        figures.dataLoadingQueue = Queue(inFlightCount: 0)
        figures.decodingQueue = Queue(inFlightCount: 0)
        figures.processingQueue = Queue(inFlightCount: nil)
        figures.decompressingQueue = Queue(inFlightCount: 0)
        figures.encodingQueue = Queue(inFlightCount: 0)
        return figures
    }
}
