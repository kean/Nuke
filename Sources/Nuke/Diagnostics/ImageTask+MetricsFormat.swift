// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

// The text report of a task: a header of facts, a line that says where the
// time went, and a tree of the jobs drawn on a chart.

extension ImageTask.Metrics {
    /// What ``ImageTask/Metrics/formatted(_:)`` prints: which sections, and
    /// which columns they decorate the rows with.
    ///
    /// Start from ``all`` and take away what a destination can't use: a log
    /// read through `grep` has no use for the chart, and a narrow terminal
    /// has none for the chart or the `URLSession` rows.
    ///
    /// ```swift
    /// print(metrics.formatted(.all.subtracting([.chart, .percentages])))
    /// ```
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        // MARK: Sections

        /// A title with the outcome, then a field per fact of the request
        /// and the result.
        public static let header = Options(rawValue: 1 << 0)
        /// A field that says where the time of the task went, by
        /// ``ImageTask/Metrics/Category``, largest first. See
        /// ``ImageTask/Metrics/timeShares``.
        public static let breakdown = Options(rawValue: 1 << 1)
        /// The tree of the jobs the task waited on, with the time the task
        /// spent on every row.
        public static let timeline = Options(rawValue: 1 << 2)
        /// The requests `URLSession` made, under the row of the download that
        /// made them. Needs ``timeline``, and prints nothing for a download
        /// the session didn't measure.
        public static let urlSession = Options(rawValue: 1 << 3)

        // MARK: Columns

        /// The chart: a lane per row, filled where the work ran on the clock
        /// of the task, so the order of the work, the gaps between it, and
        /// anything that overlapped are visible without arithmetic. Light for
        /// a wait, and a thin mark, on the cell edge nearest to when it
        /// happened, for a row too short to fill a cell.
        public static let chart = Options(rawValue: 1 << 8)
        /// The share of the task every row took, and the share of every
        /// category in ``breakdown``: what a bar can't be read off precisely,
        /// and what a row too small to draw doesn't get.
        public static let percentages = Options(rawValue: 1 << 9)
        /// The time of day the task started and finished, to line the task up
        /// with the log around it.
        public static let timestamps = Options(rawValue: 1 << 10)
        /// The digest of the key on the rows of the cache stages, so two
        /// tasks that were expected to hit the same entry can be compared.
        public static let cacheKeys = Options(rawValue: 1 << 11)

        // MARK: Presets

        /// Every section and every column: what ``ImageTask/Metrics/description``
        /// prints, and what a bug report should paste.
        public static let all: Options = [.header, .breakdown, .timeline, .urlSession, .chart, .percentages, .timestamps, .cacheKeys]

        /// The header, the breakdown, and the timeline, with none of the
        /// columns: the narrowest report, and the one that diffs cleanly
        /// between two runs.
        public static let plain: Options = [.header, .breakdown, .timeline]
    }
}

// MARK: - Description

extension ImageTask.Metrics {
    /// The width of the chart, in cells.
    private static let chartWidth = 20

    /// ``formatted(_:)`` with everything: what a bug report should paste.
    public var description: String { formatted() }

    /// A text report of the task: the sections ``Options`` asks for, in the
    /// order it lists them, separated by a blank line.
    ///
    /// The header is a title with the outcome, then a field per fact of the
    /// request and the result. A fact that says nothing – a kind that is the
    /// usual one, a task nothing coalesced with – has no field. The last
    /// field says where the time went, by ``Category``, and it adds up to the
    /// length of the task.
    ///
    /// In the timeline, the jobs form a tree, root first. The stages of a job
    /// and the job it waited on are listed under it in the order they started,
    /// so the tree reads top to bottom as the task ran. The column is the time
    /// the task spent on every row, and the chart next to it says where in the
    /// task that time was, which is what makes a gap or an overlap visible. A
    /// stage that waited a millisecond, or a tenth of the task, for its queue
    /// gets a row for the wait, named after the queue in
    /// `ImagePipeline.Configuration` and placed where the wait began. A
    /// shorter wait is folded into the stage.
    ///
    /// Under a download sit the requests `URLSession` made for it, on the same
    /// clock and the same chart: the wait for a connection, the domain lookup,
    /// the connection and its securing, the request, the wait for the first
    /// byte of the response, and the response. A step the session skipped has
    /// no row, and neither has one that was over before the task reached the
    /// download – the request it belongs to keeps its row, so what it did is
    /// still on the page. A request to the URL of the task doesn't repeat it,
    /// so a redirect stands out.
    public func formatted(_ options: Options = .all) -> String {
        var blocks: [[String]] = []

        var head: [String] = []
        var fields: [Field] = []
        if options.contains(.header) {
            head.append(title)
            fields += headerFields
        }
        if options.contains(.breakdown), let field = breakdownField(options) {
            fields.append(field)
        }
        let keyWidth = fields.map(\.key.count).max() ?? 0
        head += fields.flatMap { $0.formatted(keyWidth: keyWidth) }
        if !head.isEmpty {
            blocks.append(head)
        }

        if options.contains(.timeline) {
            blocks.append(timelineLines(options))
        }
        return blocks.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }

    // MARK: Header

    /// What a reader scans a log for: the task, how it ended, what it cost,
    /// and where the image came from.
    private var title: String {
        var title = "ImageTask #\(taskID)"
        title += label.map { " \"\($0)\"" } ?? ""
        title += " · \(outcome.rawValue) · \(time(duration))"
        title += source.map { " · from \($0.rawValue)" } ?? ""
        return title
    }

    /// A field per fact: the error first, the request, the result, and the
    /// pipeline last, since a task number is unique only within one. A fact
    /// that carries no information – the usual kind of task, a task nothing
    /// coalesced with – is left out.
    private var headerFields: [Field] {
        var fields: [Field] = []
        fields += error.map { [Field("error", text(of: $0))] } ?? []
        if kind != .image {
            fields.append(Field("kind", kind.rawValue))
        }
        fields += requestFields
        fields += resultFields
        // The first octet is enough to tell two pipelines apart in one log.
        fields.append(Field("pipeline", String(pipelineID.uuidString.prefix(8))))
        return fields
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
        fields += bytes.map { [Field("transfer", text(of: $0))] } ?? []
        if previewCount > 0 {
            fields.append(Field("previews", "\(previewCount)"))
        }
        if isCoalesced || !sharedTaskIDs.isEmpty {
            fields.append(Field("coalesced", coalescedText))
        }
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

    /// The size of the image, its format, and what it costs in memory, which
    /// is the figure a cache limit is spent on.
    private func text(of image: ImageSummary) -> String? {
        var parts: [String] = []
        if image.width > 0 || image.height > 0 {
            parts.append("\(image.width)×\(image.height)")
        }
        parts += image.format.map { [$0] } ?? []
        if image.isAnimated {
            parts.append("animated")
        }
        parts += image.memoryCost.map { ["\(Formatter.bytes($0)) in memory"] } ?? []
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The bytes the pipeline received, the part of them reused from an
    /// earlier attempt, what the server announced if the download stopped
    /// short of it, and how much of it crossed the network – which is next to
    /// nothing when the `URLCache` answered.
    private func text(of bytes: Bytes) -> String {
        var text = Formatter.bytes(bytes.downloaded)
        if bytes.expected > bytes.downloaded {
            text += " of \(Formatter.bytes(bytes.expected))"
        }
        var parts = [text]
        if bytes.resumed > 0 {
            parts.append("\(Formatter.bytes(bytes.resumed)) resumed")
        }
        // The bytes off the network are worth a word only when they
        // contradict the bytes the pipeline received, which is what a
        // `URLCache` hit does.
        if isServedFromHTTPCache, let wireBytes {
            parts.append("\(Formatter.bytes(wireBytes)) on the wire")
        }
        if isRevalidated {
            parts.append("revalidated")
        }
        return parts.joined(separator: " · ")
    }

    /// Where the time went, largest first, so the reader doesn't have to add
    /// the timeline up to find the part worth making faster.
    private func breakdownField(_ options: Options) -> Field? {
        let shares = timeShares
        guard !shares.isEmpty else { return nil }
        let parts = shares.map { share -> String in
            var text = "\(share.category.rawValue) \(ms(share.duration))"
            if options.contains(.percentages), let percent = percent(share.share) {
                text += " (\(percent))"
            }
            return text
        }
        return Field("time", parts.joined(separator: " · "))
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

    private func timelineLines(_ options: Options) -> [String] {
        var rows: [Row] = []
        if let startedAt, let span = span(from: createdAt, to: startedAt) {
            rows.append(Row(label: "pending", span: span, isWait: true, details: stamp("started", at: startedAt, options)))
        }
        var remaining = jobs
        while let root = remaining.first {
            rows += self.rows(for: root, prefixes: Prefixes(), parentJoinedAt: nil, remaining: &remaining, options: options)
        }
        // The total is not a row of the chart: it is what the chart is drawn
        // against.
        rows.append(Row(label: "total", duration: duration, details: stamp("finished", at: endedAt, options)))
        return render(rows, options)
    }

    private func stamp(_ event: String, at time: TimeInterval, _ options: Options) -> [String] {
        options.contains(.timestamps) ? ["\(event) at \(clock(time))"] : []
    }

    // MARK: Tree

    /// The rows of a job and everything under it: its stages and the job
    /// it waited on, in the order they started. Removes the jobs it prints
    /// from `remaining`, so a job no chain reaches is printed as a root of
    /// its own.
    private func rows(for job: ImagePipeline.Diagnostics.Job, prefixes: Prefixes, parentJoinedAt: TimeInterval?, remaining: inout [ImagePipeline.Diagnostics.Job], options: Options) -> [Row] {
        remaining.removeAll { $0.id == job.id }
        let span = span(of: job)
        var rows = [Row(label: prefixes.row + label(of: job), duration: span?.duration, span: span, details: details(of: job, parentJoinedAt: parentJoinedAt))]

        var entries: [Entry] = []
        for stage in job.stages {
            guard let split = split(stage, in: job) else {
                entries.append(Entry(at: stage.startedAt ?? stage.queuedAt ?? job.createdAt, kind: .stage(stage, nil)))
                continue
            }
            // The wait is an entry of its own, not a line glued above the
            // stage: a stage that runs inside the wait – the delegate the
            // pipeline asks before it downloads – belongs between the two.
            if let queue = split.queue {
                entries.append(Entry(at: queue.from, kind: .queue(stage.kind, queue)))
            }
            entries.append(Entry(at: split.body.from, kind: .stage(stage, split.body)))
        }
        entries += remaining.filter { $0.id == job.parentID }.map { Entry(at: $0.joinedAt ?? $0.createdAt, kind: .job($0)) }
        // The order of the entries breaks a tie, so a wait keeps its stage.
        entries = entries.enumerated().sorted {
            ($0.element.at, $0.offset) < ($1.element.at, $1.offset)
        }.map(\.element)

        for (index, entry) in entries.enumerated() {
            let isLast = index == entries.count - 1
            let nested = prefixes.nested(isLast: isLast)
            switch entry.kind {
            case let .queue(kind, span):
                rows.append(Row(label: nested.row + queueName(for: kind), duration: span.duration, span: span, isWait: true))
            case let .stage(stage, span):
                rows += self.rows(for: stage, in: job, span: span, prefixes: nested, options: options)
            case let .job(child):
                rows += self.rows(for: child, prefixes: nested, parentJoinedAt: job.joinedAt, remaining: &remaining, options: options)
            }
        }
        return rows
    }

    /// What draws a row's place in the tree: the branch in front of the row
    /// itself, and the one in front of everything nested under it.
    private struct Prefixes {
        var row = ""
        var children = ""

        /// The prefixes of a line under this one, given whether it is the
        /// last of them.
        func nested(isLast: Bool) -> Prefixes {
            Prefixes(row: children + (isLast ? "└─ " : "├─ "), children: children + (isLast ? "   " : "│  "))
        }
    }

    /// A line under a job, and when it starts: the wait for the queue of a
    /// stage, a stage, or the job it waited on.
    private struct Entry {
        var at: TimeInterval
        var kind: Kind

        enum Kind {
            case queue(ImagePipeline.Diagnostics.Stage.Kind, Span)
            case stage(ImagePipeline.Diagnostics.Stage, Span?)
            case job(ImagePipeline.Diagnostics.Job)
        }
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
    private func details(of job: ImagePipeline.Diagnostics.Job, parentJoinedAt: TimeInterval?) -> [String] {
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
        return parts
    }

    // MARK: Stages

    /// The wait a stage spent in its queue, when the wait is worth a row of
    /// its own, and the part of the stage that ran. `nil` for a stage the
    /// task was never there for, which has no span to draw.
    private func split(_ stage: ImagePipeline.Diagnostics.Stage, in job: ImagePipeline.Diagnostics.Job) -> (queue: Span?, body: Span)? {
        guard let span = span(of: stage, in: job) else { return nil }
        guard stage.queuedAt != nil, let startedAt = stage.startedAt else { return (nil, span) }
        let queueEnd = min(max(startedAt, span.from), span.to)
        guard isWorthARow(queueEnd - span.from, of: duration) else { return (nil, span) }
        return (Span(from: span.from, to: queueEnd), Span(from: queueEnd, to: span.to))
    }

    /// The row of a stage, above the requests `URLSession` made for it. The
    /// wait for its queue is a row of its own, placed by ``split(_:in:)``.
    private func rows(for stage: ImagePipeline.Diagnostics.Stage, in job: ImagePipeline.Diagnostics.Job, span: Span?, prefixes: Prefixes, options: Options) -> [Row] {
        let label = prefixes.row + stage.kind.rawValue
        guard let span else {
            return [Row(label: label, details: details(of: stage, in: job, options: options))]
        }
        var rows = [Row(label: label, duration: span.duration, span: span, details: details(of: stage, in: job, options: options))]
        if options.contains(.urlSession), let metrics = stage.urlSessionMetrics {
            rows += self.rows(of: metrics, prefixes: prefixes, options: options)
        }
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

    /// The details, in the same order for every kind of stage: the share of
    /// the task, the state, the result, the transfer, the output, then the
    /// timing.
    private func details(of stage: ImagePipeline.Diagnostics.Stage, in job: ImagePipeline.Diagnostics.Job, options: Options) -> [String] {
        var parts: [String] = []
        if stage.startedAt == nil {
            parts.append("never started")
        } else if stage.duration == nil {
            parts.append("running")
        }
        parts += stage.result.map { [$0.rawValue] } ?? []
        parts += transfer(of: stage) + output(of: stage) + timing(of: stage, in: job)
        if options.contains(.cacheKeys), let key = stage.cacheKey {
            parts.append("key \(key)")
        }
        if options.contains(.urlSession) {
            parts += stage.urlSessionTaskID.map { ["session #\($0)"] } ?? []
            if let count = stage.urlSessionMetrics?.redirectCount, count > 0 {
                parts.append("\(count) redirect\(count == 1 ? "" : "s")")
            }
        }
        return parts
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

    // MARK: URLSession

    /// Every request the session made for a download, each a heading with its
    /// steps under it, on the clock of the task that waited for it.
    private func rows(of metrics: ImagePipeline.Diagnostics.URLSessionMetrics, prefixes: Prefixes, options: Options) -> [Row] {
        var rows: [Row] = []
        for (index, transaction) in metrics.transactions.enumerated() {
            let nested = prefixes.nested(isLast: index == metrics.transactions.count - 1)
            let span = span(of: transaction)
            var details = details(of: transaction)
            if span == nil {
                // Either the session timed nothing for the request, which is
                // what a `URLCache` hit it answered without fetching anything
                // leaves behind, or the request ran before the task reached
                // the download, the way a stage it didn't wait for does.
                details.append(transaction.fetchStartedAt == nil ? "not timed" : "before join")
            }
            rows.append(Row(label: nested.row + transaction.fetchType.rawValue, span: span, details: details))

            let steps = self.steps(of: transaction)
            for (index, step) in steps.enumerated() {
                let line = nested.nested(isLast: index == steps.count - 1)
                rows.append(Row(label: line.row + step.name, duration: step.span.duration, span: step.span, isWait: step.isWait))
            }
        }
        return rows
    }

    /// The response, then the connection that carried it and the network it
    /// ran on: what a reader checks when a download was slow. The URL only
    /// when it isn't the one the task asked for, so a redirect stands out.
    private func details(of transaction: ImagePipeline.Diagnostics.URLSessionMetrics.Transaction) -> [String] {
        var parts: [String] = []
        if let url = transaction.url, url != request.url {
            parts.append(url)
        }
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
        return parts
    }

    /// A step of a request: the time between two of its timestamps.
    private struct Step {
        var name: String
        var span: Span
        /// `true` if the session was waiting on something else: a
        /// connection, or the server.
        var isWait = false
    }

    /// The steps the session took, in the order it took them. A step it
    /// skipped, such as the lookup for a connection it reused, is left out.
    /// The wait for a connection before the first step is a row on the terms
    /// of a queue wait.
    private func steps(of transaction: ImagePipeline.Diagnostics.URLSessionMetrics.Transaction) -> [Step] {
        var steps: [Step] = []
        func add(_ name: String, from start: TimeInterval?, to end: TimeInterval?, isWait: Bool = false) {
            guard let start, let end, end >= start, let span = span(from: start, to: end) else { return }
            steps.append(Step(name: name, span: span, isWait: isWait))
        }
        let firstStep = [transaction.domainLookupStartedAt, transaction.connectStartedAt, transaction.requestStartedAt].compactMap { $0 }.min()
        if let fetchStartedAt = transaction.fetchStartedAt, let firstStep, isWorthARow(firstStep - fetchStartedAt, of: duration) {
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

    // MARK: Rows

    /// A line of the timeline: what it is, how long the task spent on it,
    /// where in the task that was, and what else is worth knowing about it.
    private struct Row {
        var label: String
        /// `nil` for a row that is only a heading.
        var duration: TimeInterval?
        /// Where the row sits on the chart. `nil` for a row that isn't drawn.
        var span: Span?
        var isWait = false
        var details: [String] = []

        init(label: String, duration: TimeInterval? = nil, span: Span? = nil, isWait: Bool = false, details: [String] = []) {
            self.label = label
            self.duration = duration ?? span?.duration
            self.span = span
            self.isWait = isWait
            self.details = details
        }
    }

    /// The rows with the columns as wide as they need, and no wider, and with
    /// nothing trailing a line that has nothing to say.
    private func render(_ rows: [Row], _ options: Options) -> [String] {
        let labelWidth = rows.map(\.label.count).max() ?? 0
        // A row the task spent no time on – work that ran before it joined –
        // gets a mark, not a blank cell that reads as a bug.
        let values = rows.map { $0.duration.map(ms) ?? "–" }
        let valueWidth = values.map(\.count).max() ?? 0
        let shares = rows.map { row -> String in
            guard options.contains(.percentages), row.span != nil, duration > 0,
                  let rowDuration = row.duration else { return "" }
            return percent(rowDuration / duration) ?? ""
        }
        let shareWidth = shares.map(\.count).max() ?? 0

        return rows.indices.map { index in
            var line = pad(rows[index].label, to: labelWidth) + "  "
            line += pad(values[index], to: valueWidth, alignLeft: false)
            if options.contains(.chart) {
                line += "  " + chart(of: rows[index])
            }
            if shareWidth > 0 {
                line += "  " + pad(shares[index], to: shareWidth, alignLeft: false)
            }
            let details = rows[index].details.joined(separator: " · ")
            if !details.isEmpty {
                line += "  " + details
            }
            while line.hasSuffix(" ") {
                line.removeLast()
            }
            return line
        }
    }

    /// The lane of a row: the cells of the chart the row covers, so the
    /// bottleneck stands out and so does the time nothing covers. A row too
    /// short for a cell keeps a mark, on the edge it happened at.
    private func chart(of row: Row) -> String {
        var cells = [Character](repeating: " ", count: Self.chartWidth)
        guard let span = row.span, duration > 0 else { return String(cells) }
        let width = Double(Self.chartWidth)
        let scale = width / duration
        let start = min(max(0, (span.from - createdAt) * scale), width)
        let end = min(max(start, (span.to - createdAt) * scale), width)
        // A cell goes to the row that covers its middle. Rounding outwards
        // instead would stretch every bar by up to a cell at each end, so a
        // bar would outrun its own percentage and two rows that merely follow
        // one another would both claim the cell they meet in.
        let first = Int((start - 0.5).rounded(.up))
        let last = Int((end - 0.5).rounded(.up)) - 1
        guard first <= last else {
            // A row too short for a cell is a point in time, so it goes on
            // the edge the bars round to, not in the middle of the cell that
            // happens to hold it: the left edge of the cell that would start
            // there, or the right edge of the chart when nothing follows it.
            // Anything else draws work to the left of the work it came after.
            let edge = Int(((start + end) / 2 - 0.5).rounded(.up))
            cells[min(edge, Self.chartWidth - 1)] = edge < Self.chartWidth ? "▏" : "▕"
            return String(cells)
        }
        for index in max(0, first)...min(last, Self.chartWidth - 1) {
            cells[index] = row.isWait ? "░" : "█"
        }
        return String(cells)
    }

    // MARK: Formatting

    private func pad(_ text: String, to width: Int, alignLeft: Bool = true) -> String {
        let padding = String(repeating: " ", count: max(0, width - text.count))
        return alignLeft ? text + padding : padding + text
    }

    /// A share of the task. Nothing under half a percent, which would print
    /// as a zero that isn't one.
    private func percent(_ share: Double) -> String? {
        guard share >= 0.005 else { return nil }
        return "\(Int((share * 100).rounded()))%"
    }

    /// A duration for a title or a detail: milliseconds, and seconds once
    /// milliseconds stop being a number anyone reads.
    private func time(_ duration: TimeInterval) -> String {
        duration >= 10 ? String(format: "%.2f s", duration) : ms(duration)
    }

    /// A duration for the column, always in milliseconds so the rows compare,
    /// and never rounded to a `0.0 ms` that isn't true.
    private func ms(_ duration: TimeInterval) -> String {
        let milliseconds = duration * 1000
        guard milliseconds >= 0.05 else { return "<0.1 ms" }
        return String(format: "%.1f ms", milliseconds)
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
