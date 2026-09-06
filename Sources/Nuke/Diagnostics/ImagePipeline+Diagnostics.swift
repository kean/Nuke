// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImagePipeline {
    /// Records where the time of every image task went.
    ///
    /// Diagnostics are off by default. Enable them with
    /// ``ImagePipeline/Configuration-swift.struct/isDiagnosticsEnabled``:
    ///
    /// ```swift
    /// let pipeline = ImagePipeline { $0.isDiagnosticsEnabled = true }
    ///
    /// let task = pipeline.imageTask(with: url)
    /// let image = try await task.image
    /// print(task.metrics!) // A text timeline of the load
    /// ```
    ///
    /// Every task then finishes with an ``ImageTask/Metrics`` record that says
    /// where the image came from, what it cost, what the task waited on, and
    /// whether another task shared the work. The record is `Codable`,
    /// versioned with ``schemaVersion``, and reaches the pipeline delegate
    /// with the ``ImageTask/Event/finished(_:)`` event, which is where a
    /// logger picks it up.
    ///
    /// The recording is done on the pipeline actor, alongside the work it
    /// measures, and costs nothing when it is off.
    nonisolated public var diagnostics: Diagnostics { Diagnostics(pipeline: self) }

    /// The diagnostics of a pipeline. See ``ImagePipeline/diagnostics``.
    public struct Diagnostics: Sendable {
        let pipeline: ImagePipeline

        /// The version of the JSON the records encode to. It is written into
        /// every record, and bumped whenever the shape changes.
        public static let schemaVersion = 1

        /// A runtime switch. Requires
        /// ``ImagePipeline/Configuration-swift.struct/isDiagnosticsEnabled``,
        /// and is `true` by default when it is set.
        ///
        /// The switch is read once per task, when the pipeline starts it, so a
        /// task is either recorded in full or not at all. The units of work the
        /// tasks share are reported only when a recorded task reached them.
        public var isEnabled: Bool {
            get { pipeline.recorder?.isEnabled ?? false }
            nonmutating set { pipeline.recorder?.isEnabled = newValue }
        }

        /// The number of finished tasks the pipeline keeps for ``export()``.
        ///
        /// Zero by default: the pipeline retains nothing. Set it in a debug
        /// screen that wants a trace of the recent loads.
        public var retainedTaskCount: Int {
            get { pipeline.recorder?.retainedTaskCount ?? 0 }
            nonmutating set { pipeline.recorder?.retainedTaskCount = newValue }
        }

        /// Returns the tasks and units retained so far, along with the
        /// configuration that explains them.
        ///
        /// - seealso: ``retainedTaskCount``
        public func export() async -> Trace {
            guard let recorder = pipeline.recorder else {
                return Trace(pipeline: pipeline, tasks: [], units: [])
            }
            return await recorder.makeTrace(pipeline: pipeline)
        }
    }
}

// MARK: - Unit

extension ImagePipeline.Diagnostics {
    /// One piece of work the pipeline performs for a task and shares with
    /// the other tasks that need the same thing.
    ///
    /// A request becomes a chain of units: one that loads the processed image,
    /// one that decodes the original, and one that fetches its data. Two tasks
    /// coalesced on the same download see the same ``id``, which is the key
    /// to deduplicate the copies the tasks carry in ``ImageTask/Metrics/units``.
    public struct Unit: Codable, Sendable {
        /// Unique within the pipeline.
        public let id: UInt64
        public let kind: Kind
        /// The identifiers of the processors the unit applies.
        public let processors: [String]
        /// The unit this one subscribed to, which makes the chain
        /// reconstructible from a flat list.
        public let parentID: UInt64?
        /// The task whose request created the unit.
        public let createdByTaskID: UInt64
        /// Every task that reached the unit, in the order they did.
        public let taskIDs: [UInt64]
        /// The most subscribers the unit had at once: tasks plus the units
        /// that depend on it.
        public let peakSubscriberCount: Int
        /// Seconds since 1970.
        public let createdAt: TimeInterval
        /// Seconds since 1970. `nil` in a task's copy if the unit outlived
        /// the task.
        public let endedAt: TimeInterval?
        /// `nil` while the unit is running.
        public let outcome: Outcome?
        public let error: ErrorSummary?
        /// When the task the copy belongs to reached the unit, in seconds
        /// since 1970. `nil` if the task's chain created the unit, and in the
        /// copies of ``Trace/units``, which belong to no task.
        public let joinedAt: TimeInterval?
        /// The priority of the unit over time. It moves when a task joins,
        /// leaves, or changes its own priority.
        public let priorityHistory: [PriorityChange]
        public let stages: [Stage]

        /// The kind of work a unit performs.
        public enum Kind: String, Sendable, DiagnosticsStringEnum {
            /// Produces the processed, decompressed image the request asks for.
            case loadImage
            /// Decodes the original image.
            case fetchOriginalImage
            /// Fetches the original image data.
            case fetchOriginalData
            /// Produces the data ``ImagePipeline/data(for:)`` asks for.
            case loadData
            case unknown
        }
    }
}

extension ImagePipeline.Diagnostics.Unit {
    /// `nil` while the unit is running.
    public var duration: TimeInterval? {
        endedAt.map { $0 - createdAt }
    }

    public var createdDate: Date { Date(timeIntervalSince1970: createdAt) }
    public var endedDate: Date? { endedAt.map(Date.init(timeIntervalSince1970:)) }
    public var joinedDate: Date? { joinedAt.map(Date.init(timeIntervalSince1970:)) }
}

// MARK: - Stage

extension ImagePipeline.Diagnostics {
    /// A bracketed piece of work inside a unit: a cache lookup, a download,
    /// a decode.
    ///
    /// The typed fields that describe the work are optional and set only for
    /// the stages they apply to: ``result`` for the lookups, ``decoder`` and
    /// ``format`` for a decode, ``bytes`` and ``statusCode`` for a download.
    public struct Stage: Codable, Sendable {
        public let kind: Kind
        /// When the work was enqueued, in seconds since 1970. `nil` if the
        /// stage started without waiting for a queue.
        public let queuedAt: TimeInterval?
        /// Seconds since 1970. `nil` if the stage never left its queue.
        public let startedAt: TimeInterval?
        /// Measured on the pipeline actor, so it includes the hop to and from
        /// a background queue. `nil` if the stage was still running when the
        /// record was captured, or if it never started.
        public let duration: TimeInterval?
        /// Measured inside the work closure for decoding, processing,
        /// decompression, and encoding.
        public let workDuration: TimeInterval?
        /// ``duration`` clamped to the lifetime of the task the copy belongs
        /// to, so the stages a task didn't wait for attribute zero. `nil` in
        /// the copies of ``Trace/units``.
        public let attributedDuration: TimeInterval?

        /// The result of a lookup.
        public let result: LookupResult?
        /// `true` if the stage produced or handled a progressive preview.
        public let isProgressive: Bool?
        /// The type of the decoder.
        public let decoder: String?
        /// The identifier of the processor.
        public let processor: String?
        /// The type of the encoder.
        public let encoder: String?
        /// The format of the image the stage produced, such as `"jpeg"`.
        public let format: String?
        /// The size of the image the stage produced.
        public let pixels: PixelSize?
        /// The number of frames of an animated image the stage decoded.
        public let frameCount: Int?
        /// Where a download got the data from.
        public let source: Source?
        /// The bytes downloaded, read, or written.
        public let bytes: Int64?
        /// The bytes a download reused from a previous attempt.
        public let resumedBytes: Int64?
        /// The bytes a download expected, including the resumed ones.
        public let expectedBytes: Int64?
        public let chunkCount: Int?
        /// The HTTP status code of a download.
        public let statusCode: Int?
        /// When the first chunk of a download arrived, in seconds since 1970.
        public let firstByteAt: TimeInterval?
        /// The `taskIdentifier` of the `URLSessionTask` that performed the
        /// download, which links it to the metrics `URLSession` collected.
        public let urlSessionTaskID: Int?
        /// The cost of the image stored in the memory cache.
        public let cost: Int?

        /// The kind of work a stage performs.
        public enum Kind: String, Sendable, DiagnosticsStringEnum {
            case memoryLookup
            case diskLookup
            /// The time the request spent in the rate limiter.
            case rateLimit
            /// ``ImagePipeline/Delegate/willLoadData(for:urlRequest:pipeline:)``.
            case willLoadData
            case download
            case diskStore
            case decode
            case process
            case decompress
            case memoryStore
            /// Encoding a processed image for the disk cache. Runs after the
            /// tasks are done, so it appears only in ``Trace/units``.
            case encode
            case unknown
        }

        /// The result of a cache lookup.
        public enum LookupResult: String, Sendable, DiagnosticsStringEnum {
            case hit
            case miss
            case unknown
        }
    }
}

extension ImagePipeline.Diagnostics.Stage {
    /// The time the work waited for its queue.
    public var queueWait: TimeInterval? {
        guard let queuedAt, let startedAt else { return nil }
        return startedAt - queuedAt
    }

    /// Seconds since 1970. `nil` if the stage hadn't ended when the record
    /// was captured.
    public var endedAt: TimeInterval? {
        guard let startedAt, let duration else { return nil }
        return startedAt + duration
    }

    public var queuedDate: Date? { queuedAt.map(Date.init(timeIntervalSince1970:)) }
    public var startedDate: Date? { startedAt.map(Date.init(timeIntervalSince1970:)) }
    public var endedDate: Date? { endedAt.map(Date.init(timeIntervalSince1970:)) }
}

// MARK: - Shared Types

extension ImagePipeline.Diagnostics {
    /// How a task or a unit ended.
    public enum Outcome: String, Sendable, DiagnosticsStringEnum {
        case success
        case failure
        case cancelled
        case unknown
    }

    /// Where an image or its data came from.
    public enum Source: String, Sendable, DiagnosticsStringEnum {
        /// The memory cache (``ImageCaching``).
        case memory
        /// The disk cache (``DataCaching``).
        case disk
        /// The data loader (``DataLoading``), including any HTTP cache it uses.
        case network
        /// A local `file` or `data` URL.
        case file
        /// The `data` or `image` closure of the request.
        case closure
        case unknown
    }

    /// A `Codable` summary of an ``ImagePipeline/Error``.
    public struct ErrorSummary: Codable, Sendable {
        /// The name of the error case, such as `"dataLoadingFailed"`.
        public let code: String
        public let description: String
        /// The domain of the underlying `NSError`, if the error wraps one.
        public let underlyingDomain: String?
        /// The code of the underlying `NSError`, if the error wraps one.
        public let underlyingCode: Int?
    }

    /// A change of priority.
    public struct PriorityChange: Codable, Sendable {
        /// Seconds since 1970.
        public let at: TimeInterval
        public let priority: ImageRequest.Priority

        public var date: Date { Date(timeIntervalSince1970: at) }
    }

    /// A size in pixels. Encodes as a two-element array.
    public struct PixelSize: Hashable, Sendable, Codable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }

        public init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            self.width = try container.decode(Int.self)
            self.height = try container.decode(Int.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(width)
            try container.encode(height)
        }
    }
}

// MARK: - Trace

extension ImagePipeline.Diagnostics {
    /// The tasks and units a pipeline retained, with the configuration that
    /// explains their numbers.
    ///
    /// - seealso: ``ImagePipeline/Diagnostics-swift.struct/export()``
    public struct Trace: Codable, Sendable {
        public let schemaVersion: Int
        public let pipelineID: UUID
        /// Seconds since 1970.
        public let exportedAt: TimeInterval
        public let configuration: ConfigurationSummary
        /// The most recently finished tasks, oldest first.
        public let tasks: [ImageTask.Metrics]
        /// The units the retained tasks waited on, oldest first, as they were
        /// when they finished, trailing work included.
        public let units: [Unit]

        init(pipeline: ImagePipeline, tasks: [ImageTask.Metrics], units: [Unit]) {
            self.schemaVersion = ImagePipeline.Diagnostics.schemaVersion
            self.pipelineID = pipeline.id
            self.exportedAt = Date().timeIntervalSince1970
            self.configuration = ConfigurationSummary(pipeline.configuration)
            self.tasks = tasks
            self.units = units
        }
    }

    /// The parts of ``ImagePipeline/Configuration-swift.struct`` that explain
    /// the numbers in a trace: a decode queue wait means nothing without the
    /// width of the queue.
    public struct ConfigurationSummary: Codable, Sendable {
        public let isTaskCoalescingEnabled: Bool
        public let isRateLimiterEnabled: Bool
        public let isProgressiveDecodingEnabled: Bool
        public let isResumableDataEnabled: Bool
        public let isDecompressionEnabled: Bool
        /// The name of the ``ImagePipeline/DataCachePolicy``.
        public let dataCachePolicy: String
        public let hasDataCache: Bool
        public let hasImageCache: Bool
        /// The `maxConcurrentTaskCount` of the queue.
        public let dataLoadingQueue: Int
        /// The `maxConcurrentTaskCount` of the queue.
        public let imageDecodingQueue: Int
        /// The `maxConcurrentTaskCount` of the queue.
        public let imageEncodingQueue: Int
        /// The `maxConcurrentTaskCount` of the queue.
        public let imageProcessingQueue: Int
        /// The `maxConcurrentTaskCount` of the queue.
        public let imageDecompressingQueue: Int

        init(_ configuration: ImagePipeline.Configuration) {
            self.isTaskCoalescingEnabled = configuration.isTaskCoalescingEnabled
            self.isRateLimiterEnabled = configuration.isRateLimiterEnabled
            self.isProgressiveDecodingEnabled = configuration.isProgressiveDecodingEnabled
            self.isResumableDataEnabled = configuration.isResumableDataEnabled
            self.isDecompressionEnabled = configuration.isDecompressionEnabled
            self.dataCachePolicy = switch configuration.dataCachePolicy {
            case .automatic: "automatic"
            case .storeOriginalData: "storeOriginalData"
            case .storeEncodedImages: "storeEncodedImages"
            case .storeAll: "storeAll"
            }
            self.hasDataCache = configuration.dataCache != nil
            self.hasImageCache = configuration.imageCache != nil
            self.dataLoadingQueue = configuration.dataLoadingQueue.maxConcurrentTaskCount
            self.imageDecodingQueue = configuration.imageDecodingQueue.maxConcurrentTaskCount
            self.imageEncodingQueue = configuration.imageEncodingQueue.maxConcurrentTaskCount
            self.imageProcessingQueue = configuration.imageProcessingQueue.maxConcurrentTaskCount
            self.imageDecompressingQueue = configuration.imageDecompressingQueue.maxConcurrentTaskCount
        }
    }
}

// MARK: - Summary

extension ImagePipeline.Diagnostics.Trace {
    /// Aggregates the trace: outcomes, sources, coalescing, and the
    /// percentiles of every stage kind.
    ///
    /// The stage statistics are computed over the units, deduplicated by
    /// ``ImagePipeline/Diagnostics-swift.struct/Unit/id``, so a download two
    /// tasks shared is counted once.
    public func summary() -> ImagePipeline.Diagnostics.Summary {
        ImagePipeline.Diagnostics.Summary(trace: self)
    }
}

extension ImagePipeline.Diagnostics {
    /// An aggregate of a ``Trace``. See ``Trace/summary()``.
    public struct Summary: Codable, Sendable {
        public let tasks: Int
        public let succeeded: Int
        public let failed: Int
        public let cancelled: Int
        /// The number of successful tasks per ``Source``, keyed by its name.
        public let source: [String: Int]
        public let coalescing: Coalescing
        /// The statistics of every ``Stage/Kind`` that occurred, keyed by its
        /// name. Durations are seconds.
        public let stages: [String: StageSummary]
        public let bytes: Bytes
        public let configuration: ConfigurationSummary

        public struct Coalescing: Codable, Sendable {
            /// The tasks that joined a unit another task had created.
            public let coalescedTasks: Int
            /// The units more than one task reached.
            public let sharedUnits: Int
            /// The average number of tasks per shared unit.
            public let tasksPerSharedUnit: Double
        }

        public struct StageSummary: Codable, Sendable {
            public let count: Int
            public let p50: TimeInterval
            public let p95: TimeInterval
            /// `nil` for the stages that never wait for a queue.
            public let queueWaitP95: TimeInterval?
        }

        public struct Bytes: Codable, Sendable {
            public let downloaded: Int64
            public let resumed: Int64
        }

        init(trace: Trace) {
            let tasks = trace.tasks
            self.tasks = tasks.count
            self.succeeded = tasks.count { $0.outcome == .success }
            self.failed = tasks.count { $0.outcome == .failure }
            self.cancelled = tasks.count { $0.outcome == .cancelled }

            var source: [String: Int] = [:]
            for task in tasks {
                if let name = task.source?.rawValue {
                    source[name, default: 0] += 1
                }
            }
            self.source = source

            let units = Self.unitsByID(in: trace)
            let sharedUnits = units.values.filter { $0.taskIDs.count > 1 }
            self.coalescing = Coalescing(
                coalescedTasks: tasks.count { $0.isCoalesced },
                sharedUnits: sharedUnits.count,
                tasksPerSharedUnit: sharedUnits.isEmpty ? 0 : Double(sharedUnits.reduce(0) { $0 + $1.taskIDs.count }) / Double(sharedUnits.count)
            )

            let stages = units.values.flatMap(\.stages)
            self.stages = Self.stageSummaries(of: stages)
            let downloads = stages.filter { $0.kind == .download }
            self.bytes = Bytes(
                downloaded: downloads.reduce(0) { $0 + ($1.bytes ?? 0) },
                resumed: downloads.reduce(0) { $0 + ($1.resumedBytes ?? 0) }
            )
            self.configuration = trace.configuration
        }

        /// The last copy of a unit is the most complete one, and the copy sent
        /// when the unit finished is the final one.
        private static func unitsByID(in trace: Trace) -> [UInt64: Unit] {
            var units: [UInt64: Unit] = [:]
            for task in trace.tasks {
                for unit in task.units {
                    units[unit.id] = unit
                }
            }
            for unit in trace.units {
                units[unit.id] = unit
            }
            return units
        }

        private static func stageSummaries(of stages: [Stage]) -> [String: StageSummary] {
            var durations: [Stage.Kind: [TimeInterval]] = [:]
            var queueWaits: [Stage.Kind: [TimeInterval]] = [:]
            for stage in stages {
                if let duration = stage.duration {
                    durations[stage.kind, default: []].append(duration)
                }
                if let queueWait = stage.queueWait {
                    queueWaits[stage.kind, default: []].append(queueWait)
                }
            }
            var summaries: [String: StageSummary] = [:]
            for (kind, values) in durations {
                let sorted = values.sorted()
                summaries[kind.rawValue] = StageSummary(
                    count: sorted.count,
                    p50: percentile(0.5, of: sorted),
                    p95: percentile(0.95, of: sorted),
                    queueWaitP95: queueWaits[kind].map { percentile(0.95, of: $0.sorted()) }
                )
            }
            return summaries
        }
    }
}

/// Nearest-rank percentile of the sorted values.
private func percentile(_ p: Double, of sorted: [TimeInterval]) -> TimeInterval {
    guard !sorted.isEmpty else { return 0 }
    let rank = Int((p * Double(sorted.count)).rounded(.up))
    return sorted[max(0, min(sorted.count - 1, rank - 1))]
}

// MARK: - Codable Conventions

/// An enum that encodes as its lowercase name and decodes any name it doesn't
/// know as `.unknown`, so a consumer built against an older schema still opens
/// a newer file.
public protocol DiagnosticsStringEnum: RawRepresentable, Codable, Sendable where RawValue == String {
    static var unknown: Self { get }
}

extension DiagnosticsStringEnum {
    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: rawValue) ?? .unknown
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ImageRequest.Priority: Codable {
    /// Decodes the priority from its name, such as `"normal"`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        switch name {
        case "veryLow": self = .veryLow
        case "low": self = .low
        case "normal": self = .normal
        case "high": self = .high
        case "veryHigh": self = .veryHigh
        default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown priority: \(name)")
        }
    }

    /// Encodes the priority as its name, such as `"normal"`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}
