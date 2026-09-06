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
        /// Seconds since 1970.
        public let createdAt: TimeInterval
        /// Seconds since 1970. `nil` in a task's copy if the unit outlived
        /// the task.
        public let endedAt: TimeInterval?
        /// `nil` while the unit is running.
        public let outcome: Outcome?
        public let error: ErrorSummary?
        /// When the task the copy belongs to reached the unit, in seconds
        /// since 1970. `nil` if the task's chain created the unit.
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
        /// Measured inside the work closure for decoding, processing, and
        /// decompression.
        public let workDuration: TimeInterval?
        /// ``duration`` clamped to the lifetime of the task the copy belongs
        /// to, so the stages a task didn't wait for attribute zero. `nil` if
        /// the stage never started.
        public let attributedDuration: TimeInterval?

        /// The result of a lookup.
        public let result: LookupResult?
        /// `true` if the stage produced or handled a progressive preview.
        public let isProgressive: Bool?
        /// The type of the decoder.
        public let decoder: String?
        /// The identifier of the processor.
        public let processor: String?
        /// The format of the image the stage produced, such as `"jpeg"`.
        public let format: String?
        /// The size of the image the stage produced.
        public let pixels: PixelSize?
        /// Where a download got the data from.
        public let source: Source?
        /// The bytes downloaded, read, or written.
        public let bytes: Int64?
        /// The bytes a download reused from a previous attempt.
        public let resumedBytes: Int64?
        /// The bytes a download expected, including the resumed ones.
        public let expectedBytes: Int64?
        /// The HTTP status code of a download.
        public let statusCode: Int?
        /// When the first chunk of a download arrived, in seconds since 1970.
        public let firstByteAt: TimeInterval?
        /// The `taskIdentifier` of the `URLSessionTask` that performed the
        /// download. Known from the start of the download, so it is there for
        /// a task that ended before the download did, when
        /// ``urlSessionMetrics`` isn't.
        public let urlSessionTaskID: Int?
        /// What `URLSession` measured for the download: every request the
        /// session made, and the time each step of it took. `nil` if the data
        /// loader isn't a ``DataLoader``, or if the download hadn't completed
        /// when the record was captured.
        public let urlSessionMetrics: URLSessionMetrics?

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

// MARK: - URLSession

extension ImagePipeline.Diagnostics {
    /// The `Codable` subset of `URLSessionTaskMetrics`.
    public struct URLSessionMetrics: Codable, Sendable {
        /// The `taskIdentifier` of the `URLSessionTask`, which the
        /// download stage carries too, as
        /// ``ImagePipeline/Diagnostics-swift.struct/Stage/urlSessionTaskID``.
        public let urlSessionTaskID: Int
        /// When the task was resumed, in seconds since 1970.
        public let startedAt: TimeInterval
        /// When the task completed, in seconds since 1970.
        public let endedAt: TimeInterval
        public let redirectCount: Int
        /// One per request the session made, in the order it made them.
        /// A redirect adds one.
        public let transactions: [Transaction]

        /// The `Codable` subset of `URLSessionTaskTransactionMetrics`.
        ///
        /// The timestamps follow the Resource Timing model: the fetch
        /// starts, the domain is looked up, the connection is opened and
        /// secured, the request is sent, and the response arrives. A step
        /// the session skipped, such as the lookup for a connection it
        /// reused, has no timestamps.
        public struct Transaction: Codable, Sendable {
            public let url: String?
            public let statusCode: Int?
            public let fetchType: FetchType
            /// The name of the protocol, such as `"h2"`.
            public let networkProtocol: String?
            /// The version the connection negotiated, such as `"TLS 1.3"`.
            public let tlsVersion: String?
            public let remoteAddress: String?
            public let isReusedConnection: Bool
            public let isProxyConnection: Bool
            public let isCellular: Bool
            public let isExpensive: Bool
            public let isConstrained: Bool
            /// The bytes of the request, headers and body.
            public let requestBytes: Int64
            /// The bytes of the response, headers and body.
            public let responseBytes: Int64
            /// Seconds since 1970.
            public let fetchStartedAt: TimeInterval?
            public let domainLookupStartedAt: TimeInterval?
            public let domainLookupEndedAt: TimeInterval?
            public let connectStartedAt: TimeInterval?
            public let secureConnectionStartedAt: TimeInterval?
            public let secureConnectionEndedAt: TimeInterval?
            public let connectEndedAt: TimeInterval?
            public let requestStartedAt: TimeInterval?
            public let requestEndedAt: TimeInterval?
            public let responseStartedAt: TimeInterval?
            public let responseEndedAt: TimeInterval?
        }

        /// `URLSessionTaskMetrics.ResourceFetchType`.
        public enum FetchType: String, Sendable, DiagnosticsStringEnum {
            case networkLoad
            /// The `URLCache` of the session.
            case localCache
            case serverPush
            case unknown
        }
    }
}

extension ImagePipeline.Diagnostics.URLSessionMetrics {
    /// The time from the resume of the task to its completion.
    public var duration: TimeInterval { endedAt - startedAt }

    public var startedDate: Date { Date(timeIntervalSince1970: startedAt) }
    public var endedDate: Date { Date(timeIntervalSince1970: endedAt) }
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
