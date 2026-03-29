// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import CoreGraphics

/// Metrics collected during the execution of an ``ImageTask``, modeled after
/// `URLSessionTaskMetrics`.
///
/// Enable metrics collection by setting
/// ``ImagePipeline/Configuration-swift.struct/isMetricsCollectionEnabled``
/// to `true`. Once the task completes, access the metrics via
/// ``ImageTask/metrics``.
public struct ImageTaskMetrics: Codable, Sendable, CustomStringConvertible {
    /// The unique identifier of the task within its pipeline.
    public var taskId: UInt64

    /// The image identifier for the request that produced these metrics.
    /// Useful for logging and aggregation without keeping a reference to
    /// the ``ImageTask``.
    public var imageID: String?

    /// When the pipeline started executing the task.
    public var taskStartDate: Date

    /// When the task completed (success, failure, or cancellation).
    public var taskEndDate: Date

    /// Total duration.
    public var totalDuration: TimeInterval {
        taskEndDate.timeIntervalSince(taskStartDate)
    }

    /// Whether the task completed successfully.
    public var isSuccess: Bool

    /// `true` when the image was served from either the memory or disk cache.
    public var isFromCache: Bool {
        imageInfo?.cacheType != nil
    }

    /// Information about the loaded image. `nil` on failure or cancellation.
    public var imageInfo: ImageInfo?

    /// Ordered list of pipeline stages that executed for this task.
    /// Stages that were skipped (e.g., processing when there are no processors)
    /// do not appear.
    public var stages: [Stage]

    /// A lightweight summary of the loaded image.
    public struct ImageInfo: Codable, Sendable {
        /// The pixel dimensions of the final image.
        public var imageSize: CGSize
        /// The estimated decoded size of the final image in memory, in bytes.
        /// Calculated as `width * height * 4` (assuming 4 bytes per pixel).
        public var estimatedDecodedSize: Int {
            Int(imageSize.width) * Int(imageSize.height) * 4
        }
        /// The detected format of the image data (JPEG, PNG, GIF, etc.).
        public var assetType: AssetType?
        /// How the image was served: from memory cache, disk cache, or
        /// downloaded (``ImageResponse/CacheType-swift.enum``). `nil` when the
        /// image was fetched from the network or a data provider.
        public var cacheType: CacheType?
        /// Whether the final image is a progressive preview.
        public var isPreview: Bool

        /// A cache type (mirrors ``ImageResponse/CacheType-swift.enum``).
        @frozen public enum CacheType: String, Codable, Sendable {
            case memory
            case disk
        }
    }

    /// A single pipeline stage with timing and coalescing information.
    public struct Stage: Codable, Sendable {
        /// The type of work performed, with stage-specific details.
        public var type: StageType

        /// When this stage began.
        public var startDate: Date

        /// When this stage ended.
        public var endDate: Date

        /// Duration of this stage.
        public var duration: TimeInterval {
            endDate.timeIntervalSince(startDate)
        }

        /// `true` when this stage's work was shared with at least one other
        /// in-flight request via task coalescing.
        public var isFromCoalescedTask: Bool
    }

    /// The pipeline stages that can be measured.
    @frozen public enum StageType: Codable, Sendable {
        /// Memory cache lookup.
        case memoryCacheLookup(MemoryCacheLookupInfo)
        /// Disk cache lookup (includes reading data from disk).
        case diskCacheLookup(DiskCacheLookupInfo)
        /// Loading raw data from the network or a local resource.
        case dataLoading(DataLoadingInfo)
        /// Decoding image data into an image.
        case decoding(DecodingInfo)
        /// Applying an image processor.
        case processing(ProcessingInfo)
        /// Decompressing the image for rendering.
        case decompression
    }

    /// Details about a memory cache lookup.
    public struct MemoryCacheLookupInfo: Codable, Sendable {
        /// Whether the image was found in the memory cache.
        public var isHit: Bool
    }

    /// Details about a disk cache lookup.
    public struct DiskCacheLookupInfo: Codable, Sendable {
        /// Whether data was found in the disk cache.
        public var isHit: Bool
    }

    /// Details about data loading.
    public struct DataLoadingInfo: Codable, @unchecked Sendable {
        /// Total bytes downloaded.
        public var byteCount: Int64
        /// Bytes resumed from a previous partial download, if any.
        public var resumedByteCount: Int64
        /// The `URLSessionTaskMetrics` collected during data loading.
        /// Available when using the default ``DataLoader``.
        ///
        /// - note: This property is not included in `Codable` encoding.
        public var urlSessionTaskMetrics: URLSessionTaskMetrics?

        enum CodingKeys: String, CodingKey {
            case byteCount, resumedByteCount
        }
    }

    /// Details about image decoding.
    public struct DecodingInfo: Codable, Sendable {
        /// `true` if this was a progressive (partial) decode, not the final image.
        public var isProgressive: Bool
        /// The pixel dimensions of the decoded image (before processing).
        /// Compare with ``ImageInfo/imageSize`` to see the effect of processors.
        public var decodedImageSize: CGSize?
        /// A string identifying the decoder that produced the image
        /// (e.g., `"Default"`, `"Video"`).
        public var decoderType: String?
    }

    /// Details about image processing.
    public struct ProcessingInfo: Codable, Sendable {
        /// The identifier of the processor that was applied.
        public var processorIdentifier: String
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        var lines: [String] = []

        lines.append("Task {")
        lines.append("  Image ID          - \(imageID ?? "nil")")
        lines.append("  Task ID           - \(taskId)")
        lines.append("  Duration          - \(_formatInterval(taskStartDate, taskEndDate))")
        lines.append("  Result            - \(isSuccess ? "Success" : "Failure")")
        lines.append("  Is From Cache     - \(isFromCache)")
        if let info = imageInfo {
            lines.append("  Image Size        - \(Int(info.imageSize.width))×\(Int(info.imageSize.height))")
            lines.append("  Decoded Size      - \(_formatBytes(info.estimatedDecodedSize))")
            if let type = info.assetType {
                lines.append("  Asset Type        - \(type.rawValue)")
            }
            if let cache = info.cacheType {
                lines.append("  Cache Type        - \(cache)")
            }
        }
        lines.append("}")

        if !stages.isEmpty {
            lines.append("Timeline {")
            for stage in stages {
                let interval = _formatInterval(stage.startDate, stage.endDate)
                let coalesced = stage.isFromCoalescedTask ? " (coalesced)" : ""
                lines.append("  \(interval) - \(_stageName(stage.type))\(coalesced)")
                let detail = _stageDetail(stage.type)
                if !detail.isEmpty {
                    lines.append("    \(detail)")
                }
            }
            lines.append("}")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Codable Conformance for External Types

extension AssetType: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Description Helpers (Private)

private func _formatTime(_ date: Date) -> String {
    _timeFormatter.string(from: date)
}

private func _formatDuration(_ interval: TimeInterval) -> String {
    if interval < 0.001 {
        return "<1ms"
    }
    return String(format: "%.3fs", interval)
}

private func _formatInterval(_ start: Date, _ end: Date) -> String {
    let duration = end.timeIntervalSince(start)
    return "\(_formatTime(start)) – \(_formatTime(end)) (\(_formatDuration(duration)))"
}

private func _formatBytes(_ count: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .memory)
}

private func _formatBytes(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .memory)
}

private func _stageName(_ type: ImageTaskMetrics.StageType) -> String {
    switch type {
    case .memoryCacheLookup: "Memory Cache Lookup"
    case .diskCacheLookup: "Disk Cache Lookup"
    case .dataLoading: "Load Data"
    case .decoding: "Decode"
    case .processing: "Process"
    case .decompression: "Decompress"
    }
}

private func _stageDetail(_ type: ImageTaskMetrics.StageType) -> String {
    switch type {
    case .memoryCacheLookup(let info):
        return info.isHit ? "Hit" : "Miss"
    case .diskCacheLookup(let info):
        return info.isHit ? "Hit" : "Miss"
    case .dataLoading(let info):
        var parts = ["\(_formatBytes(info.byteCount))"]
        if info.resumedByteCount > 0 {
            parts.append("resumed \(_formatBytes(info.resumedByteCount))")
        }
        return parts.joined(separator: ", ")
    case .decoding(let info):
        var parts: [String] = []
        if info.isProgressive { parts.append("progressive") }
        if let size = info.decodedImageSize {
            parts.append("\(Int(size.width))×\(Int(size.height))")
        }
        if let decoder = info.decoderType {
            parts.append(decoder)
        }
        return parts.joined(separator: ", ")
    case .processing(let info):
        return info.processorIdentifier
    case .decompression:
        return ""
    }
}

private let _timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

// MARK: - ImageInfo.CacheType Bridging

extension ImageTaskMetrics.ImageInfo.CacheType {
    init(_ cacheType: ImageResponse.CacheType) {
        switch cacheType {
        case .memory: self = .memory
        case .disk: self = .disk
        }
    }
}

// MARK: - MetricsCollector (Internal)

@ImagePipelineActor
final class MetricsCollector {
    private(set) var stages: [ImageTaskMetrics.Stage] = []
    var isCoalesced = false
    var dataLoadingInfo = ImageTaskMetrics.DataLoadingInfo(byteCount: 0, resumedByteCount: 0)

    /// Tracks a synchronous stage.
    @discardableResult
    func track<T>(_ type: ImageTaskMetrics.StageType, _ work: () -> T) -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = work()
        let end = CFAbsoluteTimeGetCurrent()
        stages.append(makeStage(type, start: start, end: end))
        return result
    }

    /// Marks the start of an async stage. Returns a token to pass to ``endStage``.
    func beginStage(_ type: ImageTaskMetrics.StageType) -> Int {
        let index = stages.count
        stages.append(makeStage(type, start: CFAbsoluteTimeGetCurrent(), end: 0))
        return index
    }

    /// Updates the stage type for an in-progress stage (e.g., to add details
    /// that weren't available at `beginStage` time).
    func updateStageType(_ token: Int, _ type: ImageTaskMetrics.StageType) {
        stages[token].type = type
    }

    /// Marks the end of an async stage started with ``beginStage``.
    func endStage(_ token: Int) {
        stages[token].endDate = Date(timeIntervalSinceReferenceDate: CFAbsoluteTimeGetCurrent())
    }

    /// Merges stages from a child task, inserting them before the current stages
    /// to preserve chronological order.
    func merge(from child: MetricsCollector) {
        stages.insert(contentsOf: child.stages, at: stages.isEmpty ? 0 : findInsertionIndex())
    }

    func buildMetrics(taskId: UInt64, taskStartDate: Date, request: ImageRequest, result: Result<ImageResponse, ImagePipeline.Error>) -> ImageTaskMetrics {
        let isSuccess: Bool
        let imageInfo: ImageTaskMetrics.ImageInfo?
        switch result {
        case .success(let response):
            isSuccess = true
            imageInfo = ImageTaskMetrics.ImageInfo(
                imageSize: response.image.size,
                assetType: response.container.type,
                cacheType: response.cacheType.map(ImageTaskMetrics.ImageInfo.CacheType.init),
                isPreview: response.isPreview
            )
        case .failure:
            isSuccess = false
            imageInfo = nil
        }
        return ImageTaskMetrics(
            taskId: taskId,
            imageID: request.imageID,
            taskStartDate: taskStartDate,
            taskEndDate: Date(timeIntervalSinceReferenceDate: CFAbsoluteTimeGetCurrent()),
            isSuccess: isSuccess,
            imageInfo: imageInfo,
            stages: stages
        )
    }

    // Insert child stages before the last batch of stages added by the
    // current task (processing, decompression), but after earlier stages
    // like memoryCacheLookup.
    private func findInsertionIndex() -> Int {
        // Insert at the end of existing stages — the current task appends
        // its own stages after merging, so order is preserved.
        stages.count
    }

    private func makeStage(_ type: ImageTaskMetrics.StageType, start: CFAbsoluteTime, end: CFAbsoluteTime) -> ImageTaskMetrics.Stage {
        ImageTaskMetrics.Stage(
            type: type,
            startDate: Date(timeIntervalSinceReferenceDate: start),
            endDate: Date(timeIntervalSinceReferenceDate: end),
            isFromCoalescedTask: isCoalesced
        )
    }
}
