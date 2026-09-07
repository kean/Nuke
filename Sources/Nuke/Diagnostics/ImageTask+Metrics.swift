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
}

// MARK: - Description

extension ImageTask.Metrics {
    /// The sections of ``formatted(_:)``.
    public struct Sections: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// A title with the outcome, then a field per fact of the request
        /// and the result.
        public static let header = Sections(rawValue: 1 << 0)
        /// The tree of the jobs the task waited on, with the time the task
        /// spent on every row.
        public static let timeline = Sections(rawValue: 1 << 1)
        /// The download as `URLSession` saw it: every request the session
        /// made, with the time each step of it took. Nothing without
        /// ``urlSessionMetrics``.
        public static let urlSessionTimeline = Sections(rawValue: 1 << 2)

        public static let all: Sections = [.header, .timeline, .urlSessionTimeline]
    }

    /// ``formatted(_:)`` with every section: what a bug report should paste.
    public var description: String { formatted() }

    /// A text report of the task: the `sections`, in the order ``Sections``
    /// lists them, separated by a blank line.
    ///
    /// The header is a title with the outcome, then a field per fact of the
    /// request and the result.
    ///
    /// In the timeline, the jobs form a tree, root first. The stages of a
    /// job and the job it waited on are listed under it in the order they
    /// started, so the tree reads top to bottom as the task ran. The column is
    /// the time the task spent on every row, and the rows that took a large
    /// share of the task carry a bar next to it, light for a wait. A stage
    /// that waited a millisecond, or a tenth of the task, for its queue gets
    /// a row for the queue above it, named after the queue in
    /// `ImagePipeline.Configuration`. A shorter wait is folded into the
    /// stage. The first and the last row carry the time of day, to line the
    /// task up with the log around it.
    ///
    /// The URLSession timeline has the same shape, on the clock of the
    /// session task, which may have started before the image task joined it.
    /// Every request the session made is a heading, and the steps of the
    /// request are the rows under it: the wait for a connection, the domain
    /// lookup, the connection and its securing, the request, the wait for the
    /// first byte of the response, and the response. A step the session
    /// skipped has no row.
    public func formatted(_ sections: Sections = .all) -> String {
        var blocks: [[String]] = []
        if sections.contains(.header) {
            blocks.append(headerLines)
        }
        if sections.contains(.timeline) {
            blocks.append(timelineLines)
        }
        if sections.contains(.urlSessionTimeline), let urlSessionMetrics {
            blocks.append(lines(of: urlSessionMetrics))
        }
        return blocks.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }

    // MARK: Header

    /// A title with what a reader scans a log for, then a field per fact: the
    /// error first, the request, the result, and the pipeline last, since a
    /// task number is unique only within one.
    private var headerLines: [String] {
        var title = "ImageTask #\(taskID)"
        title += label.map { " \"\($0)\"" } ?? ""
        title += " · \(outcome.rawValue) · \(ms(duration))"
        title += source.map { " · from \($0.rawValue)" } ?? ""

        var fields: [Field] = []
        fields += error.map { [Field("error", text(of: $0))] } ?? []
        fields.append(Field("kind", kind.rawValue))
        fields += requestFields
        fields += resultFields
        fields.append(Field("pipeline", pipelineID.uuidString))

        let keyWidth = fields.map(\.key.count).max() ?? 0
        return [title] + fields.flatMap { $0.formatted(keyWidth: keyWidth) }
    }

    private var requestFields: [Field] {
        var fields: [Field] = []
        if request.url != nil || request.imageID == nil {
            fields.append(Field("url", request.url ?? "none"))
        }
        if let imageID = request.imageID, imageID != request.url {
            fields.append(Field("imageID", imageID))
        }
        fields += request.thumbnail.map { [Field("thumbnail", $0)] } ?? []
        if !request.processors.isEmpty {
            fields.append(Field("processors", request.processors))
        }
        if !request.options.isEmpty {
            fields.append(Field("options", request.options.joined(separator: ", ")))
        }
        fields.append(Field("priority", priorityText))
        return fields
    }

    private var resultFields: [Field] {
        var fields: [Field] = []
        if let image, let text = text(of: image) {
            fields.append(Field("image", text))
        }
        fields += bytes.map { [Field("download", text(of: $0))] } ?? []
        if previewCount > 0 {
            fields.append(Field("previews", "\(previewCount)"))
        }
        fields.append(Field("coalesced", coalescedText))
        return fields
    }

    /// The priority the request was created with, then every change made to
    /// the task's priority while it ran, on the task's clock.
    private var priorityText: String {
        var text = request.priority.name
        var priority = request.priority
        for change in priorityHistory where change.priority != priority {
            text += " → \(change.priority.name) at \(ms(change.at - createdAt))"
            priority = change.priority
        }
        return text
    }

    private var coalescedText: String {
        var text = isCoalesced ? "yes" : "no"
        let sharedTaskIDs = self.sharedTaskIDs
        if !sharedTaskIDs.isEmpty {
            let tasks = sharedTaskIDs.map { "#\($0)" }.joined(separator: ", ")
            let jobs = self.jobs.filter { $0.taskIDs.count > 1 }.map { "j\($0.id)" }.joined(separator: ", ")
            text += " · shared with \(tasks) (\(jobs))"
        }
        return text
    }

    /// The code and the description, which names the underlying error.
    private func text(of error: ImagePipeline.Diagnostics.ErrorSummary) -> String {
        "\(error.code) · \(error.description)"
    }

    private func text(of image: ImageSummary) -> String? {
        var parts: [String] = []
        if image.width > 0 || image.height > 0 {
            parts.append("\(image.width)×\(image.height)")
        }
        parts += image.format.map { [$0] } ?? []
        if image.isAnimated {
            parts.append("animated")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The bytes downloaded, the part of them reused from an earlier attempt,
    /// and what the server announced if the download stopped short of it.
    private func text(of bytes: Bytes) -> String {
        var text = Formatter.bytes(bytes.downloaded)
        if bytes.resumed > 0 {
            text += " (\(Formatter.bytes(bytes.resumed)) resumed)"
        }
        if bytes.expected > bytes.downloaded {
            text += " of \(Formatter.bytes(bytes.expected))"
        }
        return text
    }

    /// A fact of the header: a key and its value, or values, one per line.
    private struct Field {
        var key: String
        var values: [String]

        init(_ key: String, _ value: String) {
            self.init(key, [value])
        }

        init(_ key: String, _ values: [String]) {
            self.key = key
            self.values = values
        }

        /// The key, then the values in a column past the widest key.
        func formatted(keyWidth: Int) -> [String] {
            let indent = String(repeating: " ", count: keyWidth + 3)
            return values.enumerated().map { index, value in
                (index == 0 ? "\(key):".padding(toLength: indent.count, withPad: " ", startingAt: 0) : indent) + value
            }
        }
    }

    // MARK: Timeline

    private var timelineLines: [String] {
        var rows: [Row] = []
        if let startedAt {
            rows.append(Row(label: "started", value: ms(startedAt - createdAt), details: details(bar: bar(for: startedAt - createdAt, of: duration), ["at \(clock(startedAt))"])))
        }
        var remaining = jobs
        while let root = remaining.first {
            rows += self.rows(for: root, prefix: "", childPrefix: "", parentJoinedAt: nil, remaining: &remaining)
        }
        rows.append(Row(label: "finished", value: ms(duration), details: "at \(clock(endedAt))"))
        return format(rows)
    }

    // MARK: Tree

    /// The rows of a job and everything under it: its stages and the job
    /// it waited on, in the order they started. Removes the jobs it prints
    /// from `remaining`, so a job no chain reaches is printed as a root of
    /// its own.
    private func rows(for job: ImagePipeline.Diagnostics.Job, prefix: String, childPrefix: String, parentJoinedAt: TimeInterval?, remaining: inout [ImagePipeline.Diagnostics.Job]) -> [Row] {
        remaining.removeAll { $0.id == job.id }
        var rows = [Row(label: prefix + label(of: job), details: details(of: job, parentJoinedAt: parentJoinedAt))]

        var entries: [(at: TimeInterval, entry: Entry)] = []
        entries += job.stages.map { ($0.startedAt ?? $0.queuedAt ?? job.createdAt, .stage($0)) }
        entries += remaining.filter { $0.id == job.parentID }.map { ($0.joinedAt ?? $0.createdAt, .job($0)) }
        entries.sort { $0.at < $1.at }

        for (index, (_, entry)) in entries.enumerated() {
            let isLast = index == entries.count - 1
            let connector = isLast ? "└─ " : "├─ "
            switch entry {
            case .stage(let stage):
                rows += self.rows(for: stage, in: job, prefix: childPrefix, connector: connector)
            case .job(let child):
                rows += self.rows(for: child, prefix: childPrefix + connector, childPrefix: childPrefix + (isLast ? "   " : "│  "), parentJoinedAt: job.joinedAt, remaining: &remaining)
            }
        }
        return rows
    }

    /// A line under a job: one of its stages, or the job it waited on.
    private enum Entry {
        case stage(ImagePipeline.Diagnostics.Stage)
        case job(ImagePipeline.Diagnostics.Job)
    }

    private func label(of job: ImagePipeline.Diagnostics.Job) -> String {
        var label = "j\(job.id) \(job.kind.rawValue)"
        if !job.processors.isEmpty {
            label += " [\(job.processors.map(shortName(of:)).joined(separator: ", "))]"
        }
        return label
    }

    /// When the task joined the job, on the job's own clock, unless the
    /// parent says the same, and how the job ended, unless the task ended
    /// the same way.
    private func details(of job: ImagePipeline.Diagnostics.Job, parentJoinedAt: TimeInterval?) -> String {
        var parts: [String] = []
        if let joinedAt = job.joinedAt, joinedAt != parentJoinedAt {
            var text = "joined at \(ms(joinedAt - job.createdAt))"
            text += job.duration.map { " of \(ms($0))" } ?? ""
            parts.append(text)
        }
        if let outcome = job.outcome {
            if outcome != self.outcome {
                parts.append(outcome.rawValue)
            }
        } else {
            parts.append("running")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Stages

    /// The row of a stage, under a row for its queue when the wait for it is
    /// worth one.
    private func rows(for stage: ImagePipeline.Diagnostics.Stage, in job: ImagePipeline.Diagnostics.Job, prefix: String, connector: String) -> [Row] {
        let label = prefix + connector + stage.kind.rawValue
        guard let wait = wait(for: stage, in: job) else {
            return [Row(label: label, value: "–", details: details(of: stage, in: job, bar: nil))]
        }
        var rows: [Row] = []
        var total = wait.total
        if isWorthARow(wait.queued, of: duration) {
            rows.append(Row(label: prefix + "├─ " + queueName(for: stage.kind), value: ms(wait.queued), details: bar(for: wait.queued, of: duration, fill: "░") ?? ""))
            total -= wait.queued
        }
        let fill: Character = stage.kind == .rateLimit ? "░" : "█"
        rows.append(Row(label: label, value: ms(total), details: details(of: stage, in: job, bar: bar(for: total, of: duration, fill: fill))))
        return rows
    }

    /// A wait is a row of its own when it took a millisecond, or a tenth of
    /// the whole. A shorter one is folded into the row it held up.
    private func isWorthARow(_ wait: TimeInterval, of total: TimeInterval) -> Bool {
        wait >= 0.001 || (wait > 0 && wait >= total / 10)
    }

    /// The queue in `ImagePipeline.Configuration` a stage waits for.
    private func queueName(for kind: ImagePipeline.Diagnostics.Stage.Kind) -> String {
        switch kind {
        case .download: "dataLoadingQueue"
        case .decode: "imageDecodingQueue"
        case .process: "imageProcessingQueue"
        case .decompress: "imageDecompressingQueue"
        default: "queue"
        }
    }

    /// The time the task spent on a stage, and how much of it was the wait
    /// for the stage's queue.
    private struct Wait {
        var queued: TimeInterval = 0
        var total: TimeInterval
    }

    /// The time the task spent on the stage: from its queue to its end,
    /// clamped to the part of the stage the task was there for. Unlike
    /// ``ImagePipeline/Diagnostics-swift.struct/Stage/attributedDuration``, it
    /// includes the wait for the queue, which is where the time goes when
    /// the pipeline is busy, and says how much of it that was.
    private func wait(for stage: ImagePipeline.Diagnostics.Stage, in job: ImagePipeline.Diagnostics.Job) -> Wait? {
        guard let begin = stage.queuedAt ?? stage.startedAt else { return nil }
        let from = max(begin, job.joinedAt ?? begin)
        let to = min(stage.endedAt ?? endedAt, endedAt)
        var wait = Wait(total: max(0, to - from))
        if stage.queuedAt != nil {
            // A stage that never left its queue was queued for the whole wait.
            wait.queued = max(0, min(stage.startedAt ?? to, to) - from)
        }
        return wait
    }

    /// The details, in the same order for every kind of stage: the share of
    /// the task, the state, the result, the transfer, the output, then the
    /// timing.
    private func details(of stage: ImagePipeline.Diagnostics.Stage, in job: ImagePipeline.Diagnostics.Job, bar: String?) -> String {
        var parts: [String] = []
        if stage.startedAt == nil {
            parts.append("never started")
        } else if stage.duration == nil {
            parts.append("running")
        }
        parts += stage.result.map { [$0.rawValue] } ?? []
        parts += transfer(of: stage) + output(of: stage) + timing(of: stage, in: job)
        return details(bar: bar, parts)
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

    /// What the column doesn't say: how much of the stage was the work
    /// itself, and where in the stage the task joined, on the stage's own
    /// clock.
    private func timing(of stage: ImagePipeline.Diagnostics.Stage, in job: ImagePipeline.Diagnostics.Job) -> [String] {
        var parts: [String] = []
        if let workDuration = stage.workDuration, let duration = stage.duration, duration - workDuration >= 0.001 {
            parts.append("work \(ms(workDuration))")
        }
        if let joinedAt = job.joinedAt, let begin = stage.queuedAt ?? stage.startedAt, joinedAt > begin {
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

    /// A bar for a time that took a large share of the whole, so the
    /// bottleneck stands out without arithmetic. Light for a wait. Nothing
    /// under a millisecond.
    private func bar(for time: TimeInterval, of total: TimeInterval, fill: Character = "█") -> String? {
        guard time >= 0.001, total > 0 else { return nil }
        let width = Int((time / total * 20).rounded())
        return width >= 2 ? String(repeating: fill, count: width) : nil
    }

    /// The details of a row: its bar, then its parts.
    private func details(bar: String?, _ parts: [String]) -> String {
        let details = parts.joined(separator: " · ")
        guard let bar else { return details }
        return details.isEmpty ? bar : "\(bar)  \(details)"
    }

    // MARK: URLSession

    /// The title names the session task. The `started` row is the time the
    /// session held the task before it began to fetch, and the last row is
    /// the length of the task, both with the time of day. In between, every
    /// request is a heading with its steps under it.
    private func lines(of metrics: ImagePipeline.Diagnostics.URLSessionMetrics) -> [String] {
        var title = "URLSessionTask #\(metrics.urlSessionTaskID) · \(ms(metrics.duration))"
        if metrics.redirectCount > 0 {
            title += " · \(metrics.redirectCount) redirect\(metrics.redirectCount == 1 ? "" : "s")"
        }

        let total = metrics.duration
        var rows: [Row] = []
        let fetchStartedAt = max(metrics.transactions.first?.fetchStartedAt ?? metrics.startedAt, metrics.startedAt)
        let wait = fetchStartedAt - metrics.startedAt
        rows.append(Row(label: "started", value: ms(wait), details: details(bar: bar(for: wait, of: total), ["at \(clock(fetchStartedAt))"])))
        for transaction in metrics.transactions {
            rows.append(Row(label: transaction.fetchType.rawValue, details: details(of: transaction)))
            let steps = self.steps(of: transaction, of: total)
            for (index, step) in steps.enumerated() {
                let connector = index == steps.count - 1 ? "└─ " : "├─ "
                let fill: Character = step.isWait ? "░" : "█"
                rows.append(Row(label: connector + step.name, value: ms(step.duration), details: bar(for: step.duration, of: total, fill: fill) ?? ""))
            }
        }
        rows.append(Row(label: "finished", value: ms(total), details: "at \(clock(metrics.endedAt))"))
        return [title] + format(rows)
    }

    /// The request and the response, then the connection that carried them
    /// and the network it ran on: what a reader checks when a download was
    /// slow.
    private func details(of transaction: ImagePipeline.Diagnostics.URLSessionMetrics.Transaction) -> String {
        var parts: [String] = []
        parts += transaction.url.map { [$0] } ?? []
        parts += transaction.statusCode.map { ["HTTP \($0)"] } ?? []
        parts += transaction.networkProtocol.map { [$0] } ?? []
        parts += transaction.tlsVersion.map { [$0] } ?? []
        if transaction.isReusedConnection {
            parts.append("reused connection")
        }
        if transaction.isProxyConnection {
            parts.append("proxy")
        }
        parts += transaction.remoteAddress.map { [$0] } ?? []
        if transaction.requestBytes > 0 {
            parts.append("sent \(Formatter.bytes(transaction.requestBytes))")
        }
        if transaction.responseBytes > 0 {
            parts.append("received \(Formatter.bytes(transaction.responseBytes))")
        }
        if transaction.isCellular {
            parts.append("cellular")
        }
        if transaction.isExpensive {
            parts.append("expensive")
        }
        if transaction.isConstrained {
            parts.append("constrained")
        }
        return parts.joined(separator: " · ")
    }

    /// A step of a request: the time between two of its timestamps.
    private struct Step {
        var name: String
        var duration: TimeInterval
        /// `true` if the session was waiting on something else: a
        /// connection, or the server.
        var isWait = false
    }

    /// The steps the session took, in the order it took them. A step it
    /// skipped, such as the lookup for a connection it reused, is left out.
    /// The wait for a connection before the first step is a row on the terms
    /// of a queue wait.
    private func steps(of transaction: ImagePipeline.Diagnostics.URLSessionMetrics.Transaction, of total: TimeInterval) -> [Step] {
        var steps: [Step] = []
        func add(_ name: String, from start: TimeInterval?, to end: TimeInterval?, isWait: Bool = false) {
            guard let start, let end, end >= start else { return }
            steps.append(Step(name: name, duration: end - start, isWait: isWait))
        }
        let firstStep = [transaction.domainLookupStartedAt, transaction.connectStartedAt, transaction.requestStartedAt].compactMap { $0 }.min()
        if let fetchStartedAt = transaction.fetchStartedAt, let firstStep, isWorthARow(firstStep - fetchStartedAt, of: total) {
            add("blocked", from: fetchStartedAt, to: firstStep, isWait: true)
        }
        add("domainLookup", from: transaction.domainLookupStartedAt, to: transaction.domainLookupEndedAt)
        add("connect", from: transaction.connectStartedAt, to: transaction.secureConnectionStartedAt ?? transaction.connectEndedAt)
        add("secureConnection", from: transaction.secureConnectionStartedAt, to: transaction.secureConnectionEndedAt)
        add("request", from: transaction.requestStartedAt, to: transaction.requestEndedAt)
        add("waiting", from: transaction.requestEndedAt, to: transaction.responseStartedAt, isWait: true)
        add("response", from: transaction.responseStartedAt, to: transaction.responseEndedAt)
        return steps
    }

    // MARK: Formatting

    /// The rows with the columns as wide as they need, and no wider.
    private func format(_ rows: [Row]) -> [String] {
        let labelWidth = rows.filter { !$0.value.isEmpty }.map(\.label.count).max() ?? 0
        let valueWidth = rows.map(\.value.count).max() ?? 0
        return rows.map { $0.formatted(labelWidth: labelWidth, valueWidth: valueWidth) }
    }

    /// A line of the timeline. A stage has a value, which puts it in the
    /// columns. A job has none, and is a heading: its details follow the
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

    /// The time of day to the millisecond, in the local time zone and on a
    /// 24-hour clock whatever the locale: what Console prints next to a log
    /// line, so the two can be lined up.
    private func clock(_ time: TimeInterval) -> String {
        let format = Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))",
            timeZone: .current,
            calendar: .current
        )
        return Date(timeIntervalSince1970: time).formatted(format)
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
