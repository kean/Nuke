// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImageTask {
    /// Where the time of the task went. `nil` until the task finishes, or
    /// when diagnostics are off.
    ///
    /// The record is written into ``Status`` before the ``Event/finished(_:)``
    /// event is sent, like ``Status/result``, so it is available to the
    /// observers of that event and to anyone awaiting ``response``.
    ///
    /// - seealso: ``ImagePipeline/Configuration-swift.struct/isDiagnosticsEnabled``
    public var metrics: Metrics? { status.metrics }

    /// A record of one task: where the image came from, what it cost, what
    /// the task waited on, and whether another task shared the work.
    ///
    /// The record is self-contained. It carries a copy of every ``jobs`` the
    /// task waited on, so it can be printed, encoded, and compared without a
    /// trace. The copies keep the identifiers of the jobs, so a trace can join
    /// the records of the tasks that shared work.
    ///
    /// Coalesced work is neither double-counted nor hidden. ``duration`` is the
    /// time the task took; the ``ImagePipeline/Diagnostics-swift.struct/Stage/attributedDuration``
    /// of every stage is clamped to the lifetime of the task, so a task that
    /// joined a download halfway through attributes only the half it waited
    /// for.
    ///
    /// `description` prints a text timeline of the task, which is what a bug
    /// report should paste. ``formatted(_:)`` prints the parts of it.
    public struct Metrics: Codable, Sendable, CustomStringConvertible {
        /// The version of the JSON the record encodes to.
        public let schemaVersion: Int
        /// The pipeline that performed the task.
        public let pipelineID: UUID
        /// ``ImageTask/taskId``.
        public let taskID: UInt64
        public let kind: Kind
        /// The ``ImageRequest/UserInfoKey/labelKey`` of the request.
        public let label: String?
        public let request: RequestSummary
        /// When the task was created, in seconds since 1970.
        public let createdAt: TimeInterval
        /// When the pipeline started working on the task, in seconds since
        /// 1970. `nil` if it was cancelled before that.
        public let startedAt: TimeInterval?
        /// When the task finished, in seconds since 1970.
        public let endedAt: TimeInterval
        /// The time from creation to the finish.
        public let duration: TimeInterval
        public let outcome: ImagePipeline.Diagnostics.Outcome
        /// The error the task failed with.
        public let error: ImagePipeline.Diagnostics.ErrorSummary?
        /// Where the final image came from. Finer than
        /// ``ImageResponse/cacheType``: a processed image built from an
        /// original found on disk is ``ImagePipeline/Diagnostics-swift.struct/Source/disk``.
        /// `nil` if the task produced no image.
        public let source: ImagePipeline.Diagnostics.Source?
        /// `true` if the task attached to a job that already existed, that
        /// is, if another task started the work.
        public let isCoalesced: Bool
        /// The job the task subscribed to. `nil` if the task never started.
        public let rootJobID: UInt64?
        /// The progressive previews the task delivered.
        public let previewCount: Int
        /// The changes made to ``ImageTask/priority`` while the task ran.
        public let priorityHistory: [ImagePipeline.Diagnostics.PriorityChange]
        /// The bytes of the download the task waited on, if any.
        public let bytes: Bytes?
        /// The image the task produced.
        public let image: ImageSummary?
        /// Every job the task waited on, root first. Copies, each stamped with
        /// the time this task reached it.
        public let jobs: [ImagePipeline.Diagnostics.Job]

        /// The kind of a task.
        public enum Kind: String, Sendable, DiagnosticsStringEnum {
            /// The image loading methods, such as `imageTask(with:)`.
            case image
            /// ``ImagePipeline/data(for:)``.
            case data
            /// ``ImagePrefetcher``.
            case prefetch
            case unknown
        }

        /// The `Codable` subset of the ``ImageRequest``.
        public struct RequestSummary: Codable, Sendable {
            public let url: String?
            public let imageID: String?
            /// The identifiers of the processors.
            public let processors: [String]
            /// The identifier of ``ImageRequest/thumbnail``.
            public let thumbnail: String?
            /// The names of the ``ImageRequest/Options-swift.struct``.
            public let options: [String]
            /// The priority the request was created with.
            public let priority: ImageRequest.Priority
        }

        /// The bytes of a download.
        public struct Bytes: Codable, Sendable {
            public let downloaded: Int64
            /// The bytes reused from a previous attempt.
            public let resumed: Int64
            /// The bytes the server announced, including the resumed ones.
            public let expected: Int64
        }

        /// The image a task produced.
        public struct ImageSummary: Codable, Sendable {
            public let width: Int
            public let height: Int
            /// The format of the image data, such as `"jpeg"`.
            public let format: String?
            public let isAnimated: Bool
            /// What the image costs in memory, which is what ``ImageCache``
            /// charges it: the bitmap, plus the data an animation keeps. It
            /// dwarfs the bytes downloaded, and it is the figure a cache limit
            /// is spent on. `nil` if the image has no bitmap to measure.
            public let memoryCost: Int?
        }
    }
}

extension ImageTask.Metrics {
    public var createdDate: Date { Date(timeIntervalSince1970: createdAt) }
    public var startedDate: Date? { startedAt.map(Date.init(timeIntervalSince1970:)) }
    public var endedDate: Date { Date(timeIntervalSince1970: endedAt) }

    /// The tasks that shared a job with this one.
    public var sharedTaskIDs: [UInt64] {
        var ids: [UInt64] = []
        for job in jobs {
            for id in job.taskIDs where id != taskID && !ids.contains(id) {
                ids.append(id)
            }
        }
        return ids
    }

    /// What `URLSession` measured for the download the task waited on: the
    /// ``ImagePipeline/Diagnostics-swift.struct/Stage/urlSessionMetrics`` of
    /// its download stage. `nil` if the data loader isn't a ``DataLoader``,
    /// or if the task ended before the download did.
    public var urlSessionMetrics: ImagePipeline.Diagnostics.URLSessionMetrics? {
        for job in jobs {
            for stage in job.stages {
                if let metrics = stage.urlSessionMetrics {
                    return metrics
                }
            }
        }
        return nil
    }

    /// The bytes the session took off the network for the download the task
    /// waited on, which is far less than ``bytes`` when the response came out
    /// of the `URLCache`. `nil` unless `URLSession` measured the download.
    ///
    /// ``ImagePipeline/Diagnostics-swift.struct/Source/network`` counts a
    /// `URLCache` hit as a download, because the pipeline can't tell the
    /// difference; this can.
    public var wireBytes: Int64? { urlSessionMetrics?.networkBytesReceived }

    /// `true` if the download the task waited on was answered out of the
    /// `URLCache` of the ``DataLoader``, so ``bytes`` is what the pipeline
    /// received and not what the network carried.
    public var isServedFromHTTPCache: Bool { urlSessionMetrics?.isServedFromCache ?? false }

    /// `true` if the download the task waited on was a conditional request
    /// the server answered with `304 Not Modified`, so only the headers
    /// crossed the network and the bytes came out of the `URLCache`.
    public var isRevalidated: Bool { urlSessionMetrics?.isRevalidated ?? false }
}

// MARK: - Time Shares

extension ImageTask.Metrics {
    /// A kind of work the time of a task goes into.
    ///
    /// The categories are exclusive: when two pieces of work overlap, such as
    /// a progressive decode that runs during the download it reads from, the
    /// time counts once, for the category declared first here. So the shares
    /// of a task always add up to its ``ImageTask/Metrics/duration``.
    public enum Category: String, Sendable, CaseIterable {
        /// A download, whatever it took its bytes from.
        case network
        /// The wait for one of the queues in
        /// ``ImagePipeline/Configuration-swift.struct``, which is where the
        /// time goes when the pipeline is busy.
        case queue
        /// The wait in ``ImagePipeline/Configuration-swift.struct/rateLimiter``.
        case rateLimit
        case process
        case decompress
        case decode
        /// A cache lookup or a cache write, in memory or on disk.
        case cache
        /// What the stages don't account for: the time before the pipeline
        /// started the task, the hops between the jobs, and the work that
        /// isn't bracketed.
        case other

        /// Which category claims a stretch of time two of them cover. Lower
        /// wins, and it is the order they are declared in.
        var rank: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }
    }

    /// How much of a task one ``Category`` took.
    public struct TimeShare: Sendable {
        public let category: Category
        /// Seconds.
        public let duration: TimeInterval
        /// The share of ``ImageTask/Metrics/duration``, from 0 to 1.
        public let share: Double
    }

    /// Where the time of the task went, largest first, and
    /// ``ImageTask/Metrics/Category/other`` last.
    ///
    /// The durations add up to ``duration``, so the line answers the question
    /// the timeline leaves to arithmetic: which part of the task is worth
    /// making faster.
    public var timeShares: [TimeShare] {
        guard duration > 0 else { return [] }

        var intervals: [(category: Category, span: Span)] = []
        for job in jobs {
            for stage in job.stages {
                guard let span = span(of: stage, in: job) else { continue }
                // The wait for a queue is not the work it held up.
                if stage.queuedAt != nil, let startedAt = stage.startedAt, startedAt > span.from {
                    let queueEnd = min(startedAt, span.to)
                    intervals.append((.queue, Span(from: span.from, to: queueEnd)))
                    if queueEnd < span.to {
                        intervals.append((category(of: stage.kind), Span(from: queueEnd, to: span.to)))
                    }
                } else {
                    intervals.append((category(of: stage.kind), span))
                }
            }
        }

        // Cut the lifetime of the task at every boundary, and give each of
        // the pieces to the category that claims it, so nothing is counted
        // twice and the leftovers land in `other`.
        var points = Set([createdAt, endedAt])
        for (_, span) in intervals {
            points.insert(min(max(span.from, createdAt), endedAt))
            points.insert(min(max(span.to, createdAt), endedAt))
        }
        var totals: [Category: TimeInterval] = [:]
        let sorted = points.sorted()
        for (from, to) in zip(sorted, sorted.dropFirst()) where to > from {
            let middle = (from + to) / 2
            let category = intervals.lazy
                .filter { $0.span.contains(middle) }
                .min { $0.category.rank < $1.category.rank }?.category
            totals[category ?? .other, default: 0] += to - from
        }

        return totals
            .filter { $0.value > 0 }
            .map { TimeShare(category: $0.key, duration: $0.value, share: $0.value / duration) }
            .sorted { lhs, rhs in
                guard (lhs.category == .other) == (rhs.category == .other) else {
                    return rhs.category == .other
                }
                return lhs.duration > rhs.duration
            }
    }

    private func category(of kind: ImagePipeline.Diagnostics.Stage.Kind) -> Category {
        switch kind {
        case .download: .network
        case .rateLimit: .rateLimit
        case .process: .process
        case .decompress: .decompress
        case .decode: .decode
        case .memoryLookup, .diskLookup, .memoryStore, .diskStore: .cache
        case .willLoadData, .unknown: .other
        }
    }
}

// MARK: - Spans

extension ImageTask.Metrics {
    /// A stretch of the timeline of a task, in seconds since 1970.
    struct Span {
        var from: TimeInterval
        var to: TimeInterval

        var duration: TimeInterval { max(0, to - from) }

        func contains(_ time: TimeInterval) -> Bool { time >= from && time < to }
    }

    /// The part of a job the task was there for: from the moment it reached
    /// the job to the end of the job, clamped to the lifetime of the task.
    func span(of job: ImagePipeline.Diagnostics.Job) -> Span? {
        span(from: job.joinedAt ?? job.createdAt, to: job.endedAt)
    }

    /// The time the task spent on a stage: from its queue to its end, clamped
    /// to the part of the stage the task was there for. Unlike
    /// ``ImagePipeline/Diagnostics-swift.struct/Stage/attributedDuration``, it
    /// includes the wait for the queue, which is where the time goes when the
    /// pipeline is busy.
    func span(of stage: ImagePipeline.Diagnostics.Stage, in job: ImagePipeline.Diagnostics.Job) -> Span? {
        guard let begin = stage.queuedAt ?? stage.startedAt else { return nil }
        return span(from: max(begin, job.joinedAt ?? begin), to: stage.endedAt)
    }

    /// The request as the session timed it, from the start of the fetch to
    /// the last step it recorded.
    func span(of transaction: ImagePipeline.Diagnostics.URLSessionMetrics.Transaction) -> Span? {
        guard let from = transaction.fetchStartedAt else { return nil }
        return span(from: from, to: transaction.endedAt)
    }

    /// A span clamped to the lifetime of the task. An open end is the end of
    /// the task, which is as far as this record can see.
    func span(from: TimeInterval, to: TimeInterval?) -> Span? {
        let from = max(from, createdAt)
        let to = min(to ?? endedAt, endedAt)
        guard to >= from else { return nil }
        return Span(from: from, to: to)
    }
}

extension ImageRequest.Priority {
    var name: String {
        switch self {
        case .veryLow: "veryLow"
        case .low: "low"
        case .normal: "normal"
        case .high: "high"
        case .veryHigh: "veryHigh"
        }
    }
}
