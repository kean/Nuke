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
    /// The record is self-contained. It carries a copy of every ``units`` the
    /// task waited on, so it can be printed, encoded, and compared without a
    /// trace. The copies keep the identifiers of the units, so a trace can join
    /// the records of the tasks that shared work.
    ///
    /// Coalesced work is neither double-counted nor hidden. ``duration`` is the
    /// time the task took; the ``ImagePipeline/Diagnostics-swift.struct/Stage/attributedDuration``
    /// of every stage is clamped to the lifetime of the task, so a task that
    /// joined a download halfway through attributes only the half it waited
    /// for.
    ///
    /// `description` prints a text timeline of the task, which is what a bug
    /// report should paste.
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
        /// `true` if the task attached to a unit that already existed, that
        /// is, if another task started the work.
        public let isCoalesced: Bool
        /// The unit the task subscribed to. `nil` if the task never started.
        public let rootUnitID: UInt64?
        /// The progressive previews the task delivered.
        public let previewCount: Int
        /// The changes made to ``ImageTask/priority`` while the task ran.
        public let priorityHistory: [ImagePipeline.Diagnostics.PriorityChange]
        /// The bytes of the download the task waited on, if any.
        public let bytes: Bytes?
        /// The image the task produced.
        public let image: ImageSummary?
        /// Every unit the task waited on, root first. Copies, each stamped with
        /// the time this task reached it.
        public let units: [ImagePipeline.Diagnostics.Unit]

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
        }
    }
}

extension ImageTask.Metrics {
    public var createdDate: Date { Date(timeIntervalSince1970: createdAt) }
    public var startedDate: Date? { startedAt.map(Date.init(timeIntervalSince1970:)) }
    public var endedDate: Date { Date(timeIntervalSince1970: endedAt) }

    /// The tasks that shared a unit with this one.
    public var sharedTaskIDs: [UInt64] {
        var ids: [UInt64] = []
        for unit in units {
            for id in unit.taskIDs where id != taskID && !ids.contains(id) {
                ids.append(id)
            }
        }
        return ids
    }
}

// MARK: - Description

extension ImageTask.Metrics {
    /// A text timeline of the task. Offsets are milliseconds from the
    /// creation of the task.
    public var description: String {
        var lines = headerLines
        lines.append("")
        if let startedAt {
            lines.append("  \(offset(startedAt))  started")
        }
        for unit in units {
            lines += timelineLines(for: unit)
        }
        lines.append("  \(offset(endedAt))  finished")
        return lines.joined(separator: "\n")
    }

    private var headerLines: [String] {
        var header = "ImageTask #\(taskID) · \(kind.rawValue) · \(request.priority.name) · \(ms(duration)) · \(outcome.rawValue)"
        header += source.map { " · source: \($0.rawValue)" } ?? ""
        header += label.map { " · \($0)" } ?? ""

        var requestLine = request.url ?? request.imageID ?? "<no url>"
        if !request.processors.isEmpty {
            requestLine += " · [\(request.processors.joined(separator: ", "))]"
        }
        requestLine += request.thumbnail.map { " · thumbnail: \($0)" } ?? ""

        var lines = [header, requestLine]
        if let error {
            lines.append("error: \(error.code) · \(error.description)")
        }
        lines.append(coalescingLine)
        return lines
    }

    private var coalescingLine: String {
        var line = "coalesced: \(isCoalesced ? "yes" : "no")"
        let sharedTaskIDs = self.sharedTaskIDs
        if !sharedTaskIDs.isEmpty {
            let tasks = sharedTaskIDs.map { "#\($0)" }.joined(separator: ", ")
            let units = self.units.filter { $0.taskIDs.count > 1 }.map { "u\($0.id)" }.joined(separator: ", ")
            line += " · shared with \(tasks) (\(units))"
        }
        if previewCount > 0 {
            line += " · previews: \(previewCount)"
        }
        return line
    }

    private func timelineLines(for unit: ImagePipeline.Diagnostics.Unit) -> [String] {
        var unitLine = "  \(offset(unit.createdAt))  u\(unit.id) · \(unit.kind.rawValue)"
        if !unit.processors.isEmpty {
            unitLine += " [\(unit.processors.joined(separator: ", "))]"
        }
        unitLine += unit.joinedAt.map { " · joined at \(offset($0).trimmingCharacters(in: .whitespaces))" } ?? ""
        if unit.taskIDs.count > 1 {
            unitLine += " · tasks: \(unit.taskIDs.map { "#\($0)" }.joined(separator: ", "))"
        }
        var lines = [unitLine]
        let stages = unit.stages.map { ($0, $0.startedAt ?? $0.queuedAt ?? unit.createdAt) }
        for (stage, at) in stages.sorted(by: { $0.1 < $1.1 }) {
            let kind = stage.kind.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)
            lines.append("  \(offset(at))    \(kind) \(details(of: stage))")
        }
        if let endedAt = unit.endedAt, let outcome = unit.outcome {
            lines.append("  \(offset(endedAt))    \(outcome.rawValue)")
        }
        return lines
    }

    private func offset(_ time: TimeInterval) -> String {
        let value = String(format: "%.1f", (time - createdAt) * 1000)
        return "+\(value)".padding(toLength: 8, withPad: " ", startingAt: 0)
    }

    private func ms(_ duration: TimeInterval) -> String {
        String(format: "%.1f ms", duration * 1000)
    }

    private func details(of stage: ImagePipeline.Diagnostics.Stage) -> String {
        (timing(of: stage) + transfer(of: stage) + output(of: stage)).joined(separator: " · ")
    }

    private func timing(of stage: ImagePipeline.Diagnostics.Stage) -> [String] {
        var parts: [String] = []
        parts += stage.result.map { [$0.rawValue] } ?? []
        if let queueWait = stage.queueWait, queueWait >= 0.0001 {
            parts.append("queued \(ms(queueWait))")
        }
        switch (stage.startedAt, stage.duration) {
        case (_, let duration?):
            if duration >= 0.0001 || stage.result == nil {
                parts.append(ms(duration))
            }
        case (.some, nil):
            parts.append("running")
        case (nil, nil):
            parts.append("never started")
        }
        if let workDuration = stage.workDuration, let duration = stage.duration, duration - workDuration >= 0.001 {
            parts.append("work \(ms(workDuration))")
        }
        if let attributed = stage.attributedDuration, let duration = stage.duration, duration - attributed >= 0.0001 {
            parts.append("attributed \(ms(attributed))")
        }
        return parts
    }

    private func transfer(of stage: ImagePipeline.Diagnostics.Stage) -> [String] {
        var parts: [String] = []
        parts += stage.source.map { [$0.rawValue] } ?? []
        parts += stage.firstByteAt.map { ["first byte \(offset($0).trimmingCharacters(in: .whitespaces))"] } ?? []
        if let bytes = stage.bytes {
            var text = Formatter.bytes(bytes)
            if let resumedBytes = stage.resumedBytes, resumedBytes > 0 {
                text += " (\(Formatter.bytes(resumedBytes)) resumed)"
            }
            parts.append(text)
        }
        parts += stage.statusCode.map { ["HTTP \($0)"] } ?? []
        return parts
    }

    private func output(of stage: ImagePipeline.Diagnostics.Stage) -> [String] {
        var parts: [String] = []
        if stage.isProgressive == true {
            parts.append("preview")
        }
        parts += [stage.decoder, stage.processor, stage.format].compactMap { $0 }
        parts += stage.pixels.map { ["\($0.width)×\($0.height)"] } ?? []
        return parts
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
