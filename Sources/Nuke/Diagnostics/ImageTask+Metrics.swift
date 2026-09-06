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
    /// A text timeline of the task.
    ///
    /// The units form a tree, root first. The stages of a unit and the unit it
    /// waited on are listed under it in the order they started, so the tree
    /// reads top to bottom as the task ran. The column is the time the task
    /// spent on every stage, from its queue to its end, and the stages that
    /// took a large share of the task carry a bar next to it.
    public var description: String {
        var rows: [Row] = []
        if let startedAt {
            rows.append(Row(label: "started", value: ms(startedAt - createdAt), details: bar(for: startedAt - createdAt) ?? ""))
        }
        var remaining = units
        while let root = remaining.first {
            rows += self.rows(for: root, prefix: "", childPrefix: "", parentJoinedAt: nil, remaining: &remaining)
        }
        rows.append(Row(label: "finished", value: ms(duration)))

        // The columns are as wide as the rows need, and no wider.
        let labelWidth = rows.filter { !$0.value.isEmpty }.map(\.label.count).max() ?? 0
        let valueWidth = rows.map(\.value.count).max() ?? 0
        let lines = headerLines + [""] + rows.map { $0.formatted(labelWidth: labelWidth, valueWidth: valueWidth) }
        return lines.joined(separator: "\n")
    }

    // MARK: Header

    private var headerLines: [String] {
        var header = "ImageTask #\(taskID) · \(kind.rawValue) · \(request.priority.name) · \(ms(duration)) · \(outcome.rawValue)"
        header += source.map { " · source: \($0.rawValue)" } ?? ""
        header += label.map { " · \($0)" } ?? ""

        var requestLine = request.url ?? request.imageID ?? "<no url>"
        requestLine += request.thumbnail.map { " · thumbnail: \($0)" } ?? ""

        var lines = [header, requestLine]
        if !request.processors.isEmpty {
            lines.append("processors: [\(request.processors.joined(separator: ", "))]")
        }
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

    // MARK: Tree

    /// The rows of a unit and everything under it: its stages and the unit
    /// it waited on, in the order they started. Removes the units it prints
    /// from `remaining`, so a unit no chain reaches is printed as a root of
    /// its own.
    private func rows(for unit: ImagePipeline.Diagnostics.Unit, prefix: String, childPrefix: String, parentJoinedAt: TimeInterval?, remaining: inout [ImagePipeline.Diagnostics.Unit]) -> [Row] {
        remaining.removeAll { $0.id == unit.id }
        var rows = [Row(label: prefix + label(of: unit), details: details(of: unit, parentJoinedAt: parentJoinedAt))]

        var entries: [(at: TimeInterval, entry: Entry)] = []
        entries += unit.stages.map { ($0.startedAt ?? $0.queuedAt ?? unit.createdAt, .stage($0)) }
        entries += remaining.filter { $0.id == unit.parentID }.map { ($0.joinedAt ?? $0.createdAt, .unit($0)) }
        entries.sort { $0.at < $1.at }

        for (index, (_, entry)) in entries.enumerated() {
            let isLast = index == entries.count - 1
            let connector = isLast ? "└─ " : "├─ "
            switch entry {
            case .stage(let stage):
                rows.append(Row(label: childPrefix + connector + stage.kind.rawValue, value: wait(for: stage, in: unit).map(ms) ?? "–", details: details(of: stage, in: unit)))
            case .unit(let child):
                rows += self.rows(for: child, prefix: childPrefix + connector, childPrefix: childPrefix + (isLast ? "   " : "│  "), parentJoinedAt: unit.joinedAt, remaining: &remaining)
            }
        }
        return rows
    }

    /// A line under a unit: one of its stages, or the unit it waited on.
    private enum Entry {
        case stage(ImagePipeline.Diagnostics.Stage)
        case unit(ImagePipeline.Diagnostics.Unit)
    }

    private func label(of unit: ImagePipeline.Diagnostics.Unit) -> String {
        var label = "u\(unit.id) \(unit.kind.rawValue)"
        if !unit.processors.isEmpty {
            label += " [\(unit.processors.map(shortName(of:)).joined(separator: ", "))]"
        }
        return label
    }

    /// When the task joined the unit, on the unit's own clock, unless the
    /// parent says the same, and how the unit ended, unless the task ended
    /// the same way.
    private func details(of unit: ImagePipeline.Diagnostics.Unit, parentJoinedAt: TimeInterval?) -> String {
        var parts: [String] = []
        if let joinedAt = unit.joinedAt, joinedAt != parentJoinedAt {
            var text = "joined at \(ms(joinedAt - unit.createdAt))"
            text += unit.duration.map { " of \(ms($0))" } ?? ""
            parts.append(text)
        }
        if let outcome = unit.outcome {
            if outcome != self.outcome {
                parts.append(outcome.rawValue)
            }
        } else {
            parts.append("running")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Stages

    /// The time the task spent on the stage: from its queue to its end,
    /// clamped to the part of the stage the task was there for. Unlike
    /// ``ImagePipeline/Diagnostics-swift.struct/Stage/attributedDuration``, it
    /// includes the wait for the queue, which is where the time goes when
    /// the pipeline is busy.
    private func wait(for stage: ImagePipeline.Diagnostics.Stage, in unit: ImagePipeline.Diagnostics.Unit) -> TimeInterval? {
        guard let begin = stage.queuedAt ?? stage.startedAt else { return nil }
        let from = max(begin, unit.joinedAt ?? begin)
        let to = min(stage.endedAt ?? endedAt, endedAt)
        return max(0, to - from)
    }

    /// The details, in the same order for every kind of stage: the share of
    /// the task, the state, the result, the transfer, the output, then the
    /// timing.
    private func details(of stage: ImagePipeline.Diagnostics.Stage, in unit: ImagePipeline.Diagnostics.Unit) -> String {
        var parts: [String] = []
        if stage.startedAt == nil {
            parts.append("never started")
        } else if stage.duration == nil {
            parts.append("running")
        }
        parts += stage.result.map { [$0.rawValue] } ?? []
        parts += transfer(of: stage) + output(of: stage) + timing(of: stage, in: unit)
        let details = parts.joined(separator: " · ")
        guard let bar = wait(for: stage, in: unit).flatMap(bar(for:)) else { return details }
        return details.isEmpty ? bar : "\(bar)  \(details)"
    }

    private func transfer(of stage: ImagePipeline.Diagnostics.Stage) -> [String] {
        var parts: [String] = []
        parts += stage.source.map { [$0.rawValue] } ?? []
        if let bytes = stage.bytes {
            var text = Formatter.bytes(bytes)
            if let resumedBytes = stage.resumedBytes, resumedBytes > 0 {
                text += " (\(Formatter.bytes(resumedBytes)) resumed)"
            }
            parts.append(text)
        }
        parts += stage.statusCode.map { ["HTTP \($0)"] } ?? []
        if let firstByteAt = stage.firstByteAt, let startedAt = stage.startedAt {
            parts.append("first byte \(ms(firstByteAt - startedAt))")
        }
        return parts
    }

    private func output(of stage: ImagePipeline.Diagnostics.Stage) -> [String] {
        var parts: [String] = []
        if stage.isProgressive == true {
            parts.append("preview")
        }
        parts += stage.decoder.map { [$0] } ?? []
        let image = [stage.format, stage.pixels.map { "\($0.width)×\($0.height)" }].compactMap { $0 }
        if !image.isEmpty {
            parts.append(image.joined(separator: " "))
        }
        return parts
    }

    /// What the column doesn't say: how much of the wait was the queue, how
    /// much of the stage was the work itself, and where in the stage the
    /// task joined, on the stage's own clock.
    private func timing(of stage: ImagePipeline.Diagnostics.Stage, in unit: ImagePipeline.Diagnostics.Unit) -> [String] {
        var parts: [String] = []
        if let queueWait = stage.queueWait, queueWait >= 0.001 {
            parts.append("queued \(ms(queueWait))")
        }
        if let workDuration = stage.workDuration, let duration = stage.duration, duration - workDuration >= 0.001 {
            parts.append("work \(ms(workDuration))")
        }
        if let joinedAt = unit.joinedAt, let begin = stage.queuedAt ?? stage.startedAt, joinedAt > begin {
            if let endedAt = stage.endedAt, endedAt <= joinedAt {
                parts.append("before join")
            } else {
                var text = "joined at \(ms(joinedAt - begin))"
                text += stage.endedAt.map { " of \(ms($0 - begin))" } ?? ""
                parts.append(text)
            }
        }
        return parts
    }

    /// A bar for a wait that took a large share of the task, so the
    /// bottleneck stands out without arithmetic. Nothing under a millisecond.
    private func bar(for wait: TimeInterval) -> String? {
        guard wait >= 0.001, duration > 0 else { return nil }
        let width = Int((wait / duration * 20).rounded())
        return width >= 2 ? String(repeating: "█", count: width) : nil
    }

    // MARK: Formatting

    /// A line of the timeline. A stage has a value, which puts it in the
    /// columns. A unit has none, and is a heading: its details follow the
    /// label.
    private struct Row {
        var label: String
        var value = ""
        var details = ""

        func formatted(labelWidth: Int, valueWidth: Int) -> String {
            guard !value.isEmpty else {
                return details.isEmpty ? label : "\(label) · \(details)"
            }
            var line = label.padding(toLength: labelWidth + 2, withPad: " ", startingAt: 0)
            line += String(repeating: " ", count: valueWidth - value.count) + value
            if !details.isEmpty {
                line += "   " + details
            }
            return line
        }
    }

    private func ms(_ duration: TimeInterval) -> String {
        String(format: "%.1f ms", duration * 1000)
    }

    /// `"resize"` for `"com.github.kean/nuke/resize?s=…"`: the identifier up
    /// to its parameters, and after its namespace.
    private func shortName(of identifier: String) -> String {
        var name = Substring(identifier)
        if let end = name.firstIndex(where: { $0 == "?" || $0 == ":" || $0 == " " }) {
            name = name[..<end]
        }
        if let slash = name.lastIndex(of: "/") {
            name = name[name.index(after: slash)...]
        }
        return name.isEmpty ? identifier : String(name)
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
