// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// The text report and the arithmetic of ``ImageTask/Metrics``, on records
/// built by hand, so every field and every boundary can be reached without
/// making a pipeline produce it.
@Suite(.timeLimit(.minutes(5)))
struct ImageTaskMetricsFormatTests {

    // MARK: - Durations

    @Test(arguments: [
        (0, "<0.1 ms"),
        (0.000_04, "<0.1 ms"),
        (0.000_06, "0.1 ms"),
        (0.012_345, "12.3 ms"),
        (1.5, "1500.0 ms"),
        (9.99, "9990.0 ms"),
        (10, "10.00 s"),
        (75.5, "75.50 s"),
        (3600, "3600.00 s")
    ] as [(TimeInterval, String)])
    func titleSwitchesToSecondsAtTenSeconds(duration: TimeInterval, expected: String) {
        let metrics = _Draft(duration: duration).make()
        let title = metrics.formatted(.header).split(separator: "\n").first.map(String.init)
        #expect(title == "ImageTask #1 · success · \(expected)")
    }

    /// The column stays in milliseconds whatever the length of the task, so
    /// the rows compare.
    @Test func timelineIsAlwaysInMilliseconds() {
        let metrics = _Draft(duration: 75.5).make()
        let last = metrics.formatted(.timeline).split(separator: "\n").last.map(String.init)
        #expect(last?.range(of: #"^total +75500\.0 ms$"#, options: .regularExpression) != nil, "Unexpected row: \(last ?? "")")
    }

    /// A record of a task that took no time has nothing to break down and
    /// nothing to draw, and says so without dividing by zero.
    @Test func taskThatTookNoTimeDrawsNothing() {
        // GIVEN
        var draft = _Draft(duration: 0)
        draft.jobs = [_job(1, .loadImage, from: 0, to: 0, stages: [_stage(.memoryLookup, from: 0, duration: 0) { $0.result = .hit }])]
        let metrics = draft.make()

        // THEN
        #expect(metrics.timeShares.isEmpty)
        #expect(metrics.formatted(.breakdown).isEmpty)
        let description = metrics.description
        #expect(!description.contains("\ntime:"))
        #expect(!description.contains("█"))
        #expect(!description.contains("░"))
        #expect(!description.contains("%"))
        #expect(description.contains("j1 loadImage"))
    }

    /// A record whose end comes before its start – a corrupt one, or one
    /// written by hand – still prints.
    @Test func negativeDurationIsPrintedAsUnderATenthOfAMillisecond() {
        // GIVEN
        let metrics = _Draft(duration: -1).make()

        // THEN
        #expect(metrics.timeShares.isEmpty)
        #expect(metrics.formatted(.header).hasPrefix("ImageTask #1 · success · <0.1 ms\n"))
        let timeline = metrics.formatted(.timeline).split(separator: "\n")
        #expect(timeline.count == 1)
        #expect(timeline.first?.hasPrefix("total ") == true)
    }

    // MARK: - Header

    @Test func headerNamesTheImageIDOnlyWhenItIsNotTheURL() {
        func header(url: String?, imageID: String?) -> String {
            var draft = _Draft()
            draft.url = url
            draft.imageID = imageID
            return draft.make().formatted(.header)
        }

        // A closure request has no URL
        let closure = header(url: nil, imageID: "avatar-42")
        #expect(closure.range(of: #"\nimageID: +avatar-42\n"#, options: .regularExpression) != nil, "Unexpected header:\n\(closure)")
        #expect(!closure.contains("\nurl:"))

        // A request with neither says so rather than leaving the field out
        let none = header(url: nil, imageID: nil)
        #expect(none.range(of: #"\nurl: +none\n"#, options: .regularExpression) != nil, "Unexpected header:\n\(none)")
        #expect(!none.contains("\nimageID:"))

        // A custom ID is printed next to the URL
        let custom = header(url: "https://example.com/a.jpeg?token=1", imageID: "https://example.com/a.jpeg")
        #expect(custom.range(of: #"\nurl: +https://example\.com/a\.jpeg\?token=1\nimageID: +https://example\.com/a\.jpeg\n"#, options: .regularExpression) != nil, "Unexpected header:\n\(custom)")

        // The default one isn't
        let plain = header(url: "https://example.com/a.jpeg", imageID: "https://example.com/a.jpeg")
        #expect(!plain.contains("\nimageID:"))
    }

    @Test func headerPrintsEveryProcessorOnALineOfItsOwn() throws {
        // GIVEN
        var draft = _Draft()
        draft.processors = ["com.example/first?a=1", "com.example/second"]
        let header = draft.make().formatted(.header)
        let lines = header.split(separator: "\n").map(String.init)

        // THEN the second value sits in the column of the first
        let index = try #require(lines.firstIndex { $0.hasPrefix("processors:") }, "No processors in:\n\(header)")
        let column = try #require(lines[index].range(of: "com.example/first")).lowerBound
        let offset = lines[index].distance(from: lines[index].startIndex, to: column)
        #expect(lines[index + 1] == String(repeating: " ", count: offset) + "com.example/second", "Unexpected header:\n\(header)")

        // THEN every field has its value in that column
        for line in lines.dropFirst() {
            let value = try #require(line.range(of: #"^([a-zA-Z]+: +| +)"#, options: .regularExpression), "Unexpected line: \(line)")
            #expect(line.distance(from: line.startIndex, to: value.upperBound) == offset, "Misaligned header:\n\(header)")
        }
    }

    @Test func headerPrintsTheErrorFirst() {
        // GIVEN
        var draft = _Draft()
        draft.outcome = .failure
        draft.error = ImagePipeline.Diagnostics.ErrorSummary(code: "decodingFailed", description: "Failed to decode the image", underlyingDomain: nil, underlyingCode: nil)
        let lines = draft.make().formatted(.header).split(separator: "\n").map(String.init)

        // THEN
        #expect(lines.first == "ImageTask #1 · failure · 100.0 ms")
        #expect(lines.count > 1)
        #expect(lines[1].range(of: #"^error: +decodingFailed · Failed to decode the image$"#, options: .regularExpression) != nil, "Unexpected header:\n\(lines.joined(separator: "\n"))")
    }

    @Test func headerPrintsTheKindOnlyWhenItIsNotTheUsualOne() {
        for (kind, name) in [(ImageTask.Metrics.Kind.data, "data"), (.prefetch, "prefetch"), (.unknown, "unknown")] {
            var draft = _Draft()
            draft.kind = kind
            let header = draft.make().formatted(.header)
            #expect(header.range(of: "\nkind: +\(name)\n", options: .regularExpression) != nil, "Unexpected header:\n\(header)")
        }
        #expect(!_Draft().make().formatted(.header).contains("\nkind:"))
    }

    @Test func headerCountsThePreviews() {
        var draft = _Draft()
        draft.previewCount = 3
        #expect(draft.make().formatted(.header).range(of: #"\npreviews: +3\n"#, options: .regularExpression) != nil)
        #expect(!_Draft().make().formatted(.header).contains("\npreviews:"))
    }

    @Test func headerDescribesTheImage() {
        func imageField(_ image: ImageTask.Metrics.ImageSummary) -> String? {
            var draft = _Draft()
            draft.image = image
            let header = draft.make().formatted(.header)
            return header.split(separator: "\n").first { $0.hasPrefix("image:") }.map {
                String($0.dropFirst("image:".count)).trimmingCharacters(in: .whitespaces)
            }
        }

        #expect(imageField(.init(width: 10, height: 20, format: "gif", isAnimated: true, memoryCost: 800)) == "10×20 · gif · animated · \(Formatter.bytes(800)) in memory")
        #expect(imageField(.init(width: 10, height: 20, format: nil, isAnimated: false, memoryCost: nil)) == "10×20")
        // No bitmap to measure: the format is what's left to say
        #expect(imageField(.init(width: 0, height: 0, format: "png", isAnimated: false, memoryCost: nil)) == "png")
        // Nothing to say, no field
        #expect(imageField(.init(width: 0, height: 0, format: nil, isAnimated: false, memoryCost: nil)) == nil)
    }

    @Test func headerDescribesTheTransfer() {
        func transferField(_ bytes: ImageTask.Metrics.Bytes) -> String? {
            var draft = _Draft()
            draft.bytes = bytes
            let header = draft.make().formatted(.header)
            return header.split(separator: "\n").first { $0.hasPrefix("transfer:") }.map {
                String($0.dropFirst("transfer:".count)).trimmingCharacters(in: .whitespaces)
            }
        }

        // A download that stopped short says what the server announced
        #expect(transferField(.init(downloaded: 1_000, resumed: 0, expected: 50_000)) == "\(Formatter.bytes(1_000)) of \(Formatter.bytes(50_000))")
        // A resumed one says how much of it was reused
        #expect(transferField(.init(downloaded: 50_000, resumed: 20_000, expected: 50_000)) == "\(Formatter.bytes(50_000)) · \(Formatter.bytes(20_000)) resumed")
        // An announcement the server didn't keep isn't worth a word
        #expect(transferField(.init(downloaded: 50_000, resumed: 0, expected: 1_000)) == Formatter.bytes(50_000))
        #expect(transferField(.init(downloaded: 0, resumed: 0, expected: 0)) == Formatter.bytes(0))
    }

    /// The bytes on the wire are worth a word only when the `URLCache`
    /// answered, which is when they contradict the bytes received.
    @Test func headerNamesTheBytesOnTheWireOnlyForAURLCacheHit() {
        func header(fetchType: ImagePipeline.Diagnostics.URLSessionMetrics.FetchType, statusCode: Int) -> String {
            var draft = _Draft()
            draft.bytes = .init(downloaded: 40_000, resumed: 0, expected: 40_000)
            let transaction = _transaction(fetchType: fetchType, statusCode: statusCode, responseBytes: 300, from: 0)
            draft.jobs = [_job(1, .fetchOriginalData, from: 0, to: 0.1, stages: [
                _stage(.download, from: 0, duration: 0.1) {
                    $0.urlSessionTaskID = 7
                    $0.urlSessionMetrics = .init(urlSessionTaskID: 7, startedAt: _t0, endedAt: _t0 + 0.1, redirectCount: 0, transactions: [transaction])
                }
            ])]
            return draft.make().formatted(.header)
        }

        let network = header(fetchType: .networkLoad, statusCode: 200)
        #expect(network.range(of: "\ntransfer: +\(Formatter.bytes(40_000))\n", options: .regularExpression) != nil, "Unexpected header:\n\(network)")

        let cache = header(fetchType: .localCache, statusCode: 200)
        #expect(cache.contains("\(Formatter.bytes(40_000)) · \(Formatter.bytes(0)) on the wire\n"), "Unexpected header:\n\(cache)")

        let revalidated = header(fetchType: .networkLoad, statusCode: 304)
        #expect(revalidated.contains("\(Formatter.bytes(40_000)) · revalidated\n"), "Unexpected header:\n\(revalidated)")
    }

    /// Every change made to the priority is listed on the task's clock,
    /// except those that changed nothing.
    @Test func headerListsOnlyThePriorityChangesThatChangedSomething() {
        // GIVEN
        var draft = _Draft()
        draft.priority = .normal
        draft.priorityHistory = [
            .init(at: _t0 + 0.001, priority: .normal),
            .init(at: _t0 + 0.002, priority: .high),
            .init(at: _t0 + 0.003, priority: .high),
            .init(at: _t0 + 0.004, priority: .veryLow)
        ]

        // THEN
        let header = draft.make().formatted(.header)
        #expect(header.range(of: #"\npriority: +normal → high at 2\.0 ms → veryLow at 4\.0 ms\n"#, options: .regularExpression) != nil, "Unexpected header:\n\(header)")
    }

    /// The task that started the work isn't coalesced, but it did share it.
    @Test func headerOfTheTaskThatStartedSharedWorkNamesTheOthers() {
        // GIVEN
        var draft = _Draft()
        draft.jobs = [
            _job(1, .loadImage, parent: 2, from: 0, to: 0.1),
            _job(2, .fetchOriginalImage, parent: 3, from: 0, to: 0.1, taskIDs: [1, 5]),
            _job(3, .fetchOriginalData, from: 0, to: 0.1, taskIDs: [1, 5, 9])
        ]
        let metrics = draft.make()

        // THEN
        #expect(metrics.sharedTaskIDs == [5, 9])
        let header = metrics.formatted(.header)
        #expect(header.range(of: #"\ncoalesced: +no · shared with #5, #9 \(j2, j3\)\n"#, options: .regularExpression) != nil, "Unexpected header:\n\(header)")
    }

    // MARK: - Breakdown

    /// When two stages overlap, the category declared first claims the time,
    /// so nothing is counted twice.
    @Test func overlappingStagesAreCountedOnceForTheCategoryDeclaredFirst() throws {
        // GIVEN a progressive decode that runs during the download it reads
        // from, and a process that overlaps a decompression
        var draft = _Draft(duration: 1)
        draft.jobs = [_job(1, .fetchOriginalData, from: 0, to: 1, stages: [
            _stage(.download, from: 0, duration: 0.4),
            _stage(.decode, from: 0.3, duration: 0.2),
            _stage(.decompress, from: 0.5, duration: 0.2),
            _stage(.process, from: 0.6, duration: 0.2)
        ])]
        let metrics = draft.make()

        // THEN
        let shares = Dictionary(uniqueKeysWithValues: metrics.timeShares.map { ($0.category, $0.duration) })
        #expect(abs(try #require(shares[.network]) - 0.4) < 1e-9)
        #expect(abs(try #require(shares[.decode]) - 0.1) < 1e-9)
        #expect(abs(try #require(shares[.decompress]) - 0.1) < 1e-9)
        #expect(abs(try #require(shares[.process]) - 0.2) < 1e-9)
        #expect(abs(try #require(shares[.other]) - 0.2) < 1e-9)
        #expect(abs(metrics.timeShares.map(\.share).reduce(0, +) - 1) < 1e-9)
        // Largest first, and `other` last
        #expect(metrics.timeShares.prefix(2).map(\.category) == [.network, .process])
        #expect(metrics.timeShares.last?.category == .other)
        // "Lower wins, and it is the order they are declared in"
        #expect(ImageTask.Metrics.Category.allCases == [.network, .queue, .rateLimit, .process, .decompress, .decode, .cache, .other])
    }

    @Test func otherIsLastEvenWhenItIsTheLargest() {
        var draft = _Draft(duration: 1)
        draft.jobs = [_job(1, .loadImage, from: 0, to: 1, stages: [_stage(.memoryLookup, from: 0, duration: 0.1)])]
        let shares = draft.make().timeShares
        #expect(shares.map(\.category) == [.cache, .other])
        #expect(abs(shares[1].share - 0.9) < 1e-9)
    }

    /// The wait for a queue is not the work it held up.
    @Test func queueWaitIsItsOwnCategory() throws {
        // GIVEN a download that waited 300 ms for its queue, then ran 500 ms
        var draft = _Draft(duration: 1)
        draft.jobs = [_job(1, .fetchOriginalData, from: 0, to: 0.8, stages: [
            _stage(.download, queued: 0, from: 0.3, duration: 0.5)
        ])]
        let metrics = draft.make()

        // THEN
        let shares = Dictionary(uniqueKeysWithValues: metrics.timeShares.map { ($0.category, $0.duration) })
        #expect(abs(try #require(shares[.queue]) - 0.3) < 1e-9)
        #expect(abs(try #require(shares[.network]) - 0.5) < 1e-9)
        #expect(abs(try #require(shares[.other]) - 0.2) < 1e-9)
        #expect(metrics.timeShares.map(\.category) == [.network, .queue, .other])

        // THEN the line says the same
        let line = metrics.formatted([.breakdown, .percentages])
        #expect(line.range(of: #"^time: +network 500\.0 ms \(50%\) · queue 300\.0 ms \(30%\) · other 200\.0 ms \(20%\)$"#, options: .regularExpression) != nil, "Unexpected breakdown: \(line)")
        #expect(metrics.formatted(.breakdown).range(of: #"^time: +network 500\.0 ms · queue 300\.0 ms · other 200\.0 ms$"#, options: .regularExpression) != nil)
    }

    /// A stage that never left its queue is all wait, drawn light and named
    /// after the queue.
    @Test func neverStartedStageIsAWait() throws {
        // GIVEN a task cancelled while its download waited for its queue
        var draft = _Draft(duration: 1)
        draft.outcome = .cancelled
        draft.jobs = [_job(1, .fetchOriginalData, from: 0, to: 1, outcome: .cancelled, stages: [
            _stage(.download, queued: 0, from: nil, duration: nil)
        ])]
        let metrics = draft.make()

        // THEN the whole task is the wait
        #expect(metrics.timeShares.map(\.category) == [.queue], "Unexpected shares: \(metrics.timeShares)")

        // THEN the wait is a light row named after the queue, and the stage
        // has nothing to draw
        let timeline = metrics.formatted([.timeline, .chart])
        let lines = timeline.split(separator: "\n")
        let wait = try #require(lines.first { $0.contains("─ dataLoadingQueue ") }, "No queue row in:\n\(timeline)")
        #expect(wait.contains("░") && !wait.contains("█"), "Unexpected row: \(wait)")
        let download = try #require(lines.first { $0.contains("─ download ") })
        #expect(!download.contains("█") && !download.contains("░"), "Unexpected row: \(download)")
        #expect(download.hasSuffix("  never started"), "Unexpected row: \(download)")
    }

    /// The wait of a stage that never left its queue ends when the stage that
    /// replaced it is enqueued: it doesn't claim the work that followed.
    @Test func replacedStageWaitsUntilItsReplacementIsEnqueued() throws {
        // GIVEN a progressive process that waited 200 ms, then was replaced
        // by the final one, which waited 100 ms and ran 300 ms
        var draft = _Draft(duration: 1)
        draft.jobs = [_job(1, .loadImage, from: 0, to: 1, stages: [
            _stage(.process, queued: 0.1, from: nil, duration: nil),
            _stage(.process, queued: 0.3, from: 0.4, duration: 0.3)
        ])]
        let metrics = draft.make()

        // THEN
        let shares = Dictionary(uniqueKeysWithValues: metrics.timeShares.map { ($0.category, $0.duration) })
        #expect(abs(try #require(shares[.queue]) - 0.3) < 1e-9)
        #expect(abs(try #require(shares[.process]) - 0.3) < 1e-9)
        #expect(abs(try #require(shares[.other]) - 0.4) < 1e-9)
    }

    /// A task that joined a stage halfway through is charged from the join.
    @Test func coalescedTaskIsChargedFromTheJoin() throws {
        // GIVEN a task that joined a download 300 ms into it
        var draft = _Draft(duration: 0.4)
        draft.createdAt = _t0 + 0.25
        draft.startedAt = _t0 + 0.25
        draft.isCoalesced = true
        draft.jobs = [_job(1, .fetchOriginalData, from: 0, to: 0.6, taskIDs: [7, 1], joinedAt: 0.3, stages: [
            _stage(.download, from: 0, duration: 0.6)
        ])]
        let metrics = draft.make()

        // THEN only the part it waited for is network time
        let shares = Dictionary(uniqueKeysWithValues: metrics.timeShares.map { ($0.category, $0.duration) })
        #expect(abs(try #require(shares[.network]) - 0.3) < 1e-9)
        #expect(abs(try #require(shares[.other]) - 0.1) < 1e-9)
    }

    @Test func percentagesUnderHalfAPercentAreLeftOut() {
        // GIVEN a stage that took 0.4% of the task
        var draft = _Draft(duration: 1)
        draft.jobs = [_job(1, .loadImage, from: 0, to: 1, stages: [_stage(.memoryLookup, from: 0, duration: 0.004)])]
        let metrics = draft.make()

        // THEN
        let line = metrics.formatted([.breakdown, .percentages])
        #expect(line.range(of: #"^time: +cache 4\.0 ms · other 996\.0 ms \(100%\)$"#, options: .regularExpression) != nil, "Unexpected breakdown: \(line)")
        #expect(!metrics.formatted(.breakdown).contains("%"))
    }

    /// The records that pin the schema are real loads: whatever they did,
    /// their breakdown adds up to their length, and no stage is charged more
    /// than the task lasted.
    @Test(arguments: ["diagnostics-metrics", "diagnostics-metrics-revalidated"])
    func fixturesBreakDownIntoTheirDuration(name: String) throws {
        // GIVEN
        let metrics = try JSONDecoder().decode(ImageTask.Metrics.self, from: Test.data(name: name, extension: "json"))

        // THEN the shares partition the task, to the precision of timestamps
        // that are seconds since 1970 (a fraction of a microsecond)
        let shares = metrics.timeShares
        #expect(!shares.isEmpty)
        #expect(abs(shares.map(\.duration).reduce(0, +) - metrics.duration) < 1e-6)
        #expect(abs(shares.map(\.share).reduce(0, +) - 1) < 1e-5)
        #expect(Set(shares.map(\.category)).count == shares.count)
        for stage in metrics.jobs.flatMap(\.stages) {
            guard let attributed = stage.attributedDuration else { continue }
            #expect(attributed >= 0)
            #expect(attributed <= metrics.duration + 1e-9)
            #expect(attributed <= (stage.duration ?? .infinity) + 1e-9)
        }
    }

    // MARK: - Options

    /// The columns decorate the sections: without one, they print nothing.
    @Test func columnsWithoutASectionPrintNothing() throws {
        let metrics = try JSONDecoder().decode(ImageTask.Metrics.self, from: Test.data(name: "diagnostics-metrics", extension: "json"))
        #expect(metrics.formatted([.chart, .percentages, .timestamps, .cacheKeys]).isEmpty)
        // The requests `URLSession` made need the timeline to sit in
        #expect(metrics.formatted(.urlSession).isEmpty)
        #expect(metrics.formatted([.header, .urlSession]) == metrics.formatted(.header))
        #expect(metrics.formatted([.timeline, .urlSession]).contains("─ networkLoad "))
    }

    // MARK: - Timeline

    @Test func jobRowsSayHowTheJobEndedWhenTheTaskEndedDifferently() throws {
        // GIVEN a failed task: its root failed, the download it read
        // succeeded, and a job it had joined was still running
        var draft = _Draft(duration: 1)
        draft.outcome = .failure
        draft.jobs = [
            _job(1, .loadImage, parent: 2, from: 0, to: 0.9, outcome: .failure),
            _job(2, .fetchOriginalImage, parent: 3, from: 0, to: nil, outcome: nil, taskIDs: [4, 1], joinedAt: 0.2),
            _job(3, .fetchOriginalData, from: -0.1, to: 0.5, outcome: .success, taskIDs: [4, 1], joinedAt: 0.2)
        ]
        let lines = draft.make().formatted(.timeline).split(separator: "\n").map(String.init)

        // THEN
        let root = try #require(lines.first { $0.hasPrefix("j1 loadImage") })
        #expect(!root.contains("failure"), "Unexpected row: \(root)")
        let running = try #require(lines.first { $0.contains("j2 fetchOriginalImage") })
        #expect(running.hasSuffix("  joined at 200.0 ms · running"), "Unexpected row: \(running)")
        let succeeded = try #require(lines.first { $0.contains("j3 fetchOriginalData") })
        // The parent said when the task joined, so the child doesn't repeat it
        #expect(succeeded.hasSuffix("  success"), "Unexpected row: \(succeeded)")
        #expect(!succeeded.contains("joined at"), "Unexpected row: \(succeeded)")
    }

    @Test func joinedJobSaysWhereInItTheTaskJoined() throws {
        // GIVEN
        var draft = _Draft(duration: 1)
        draft.isCoalesced = true
        draft.jobs = [_job(1, .loadImage, from: -0.1, to: 0.5, taskIDs: [2, 1], joinedAt: 0.05)]
        let lines = draft.make().formatted(.timeline).split(separator: "\n").map(String.init)

        // THEN on the job's own clock
        let row = try #require(lines.first { $0.hasPrefix("j1 loadImage") })
        #expect(row.hasSuffix("  joined at 150.0 ms of 600.0 ms"), "Unexpected row: \(row)")
    }

    @Test func stageRowsSayWhatStateTheStageIsIn() throws {
        // GIVEN
        var draft = _Draft(duration: 1)
        draft.outcome = .cancelled
        draft.jobs = [_job(1, .fetchOriginalData, from: 0, to: 1, outcome: .cancelled, stages: [
            _stage(.download, from: 0, duration: 0.2) {
                $0.source = .network
                $0.bytes = 30_000
                $0.resumedBytes = 10_000
                $0.statusCode = 206
                $0.firstByteAt = _t0 + 0.05
            },
            _stage(.decode, from: 0.2, duration: 0.1) {
                $0.isProgressive = true
                $0.decoder = "ImageDecoders.Default"
                $0.format = "jpeg"
                $0.pixels = .init(width: 64, height: 48)
                $0.workDuration = 0.02
            },
            _stage(.process, from: 0.3, duration: 0.1) {
                $0.processor = "resize"
                $0.workDuration = 0.0995
            },
            _stage(.decompress, from: 0.5, duration: nil),
            _stage(.decode, queued: 0.6, from: nil, duration: nil)
        ])]
        let lines = draft.make().formatted(.timeline).split(separator: "\n").map(String.init)
        func row(_ needle: String, _ index: Int = 0) throws -> String {
            try #require(lines.filter { $0.contains(needle) }.dropFirst(index).first, "No \(needle) in:\n\(lines.joined(separator: "\n"))")
        }

        // THEN
        let download = try row("─ download ")
        #expect(download.hasSuffix("  network · \(Formatter.bytes(30_000)) (\(Formatter.bytes(10_000)) resumed) · HTTP 206 · first byte 50.0 ms"), "Unexpected row: \(download)")
        let decode = try row("─ decode ")
        #expect(decode.hasSuffix("  preview · ImageDecoders.Default · jpeg 64×48 · work 20.0 ms"), "Unexpected row: \(decode)")
        // The work took all of the stage, give or take the hop: not worth a word
        let process = try row("─ process ")
        #expect(!process.contains("work"), "Unexpected row: \(process)")
        let decompress = try row("─ decompress ")
        #expect(decompress.hasSuffix("  running"), "Unexpected row: \(decompress)")
        let queued = try row("─ decode ", 1)
        #expect(queued.hasSuffix("  never started"), "Unexpected row: \(queued)")
    }

    @Test func stageBeforeTheJoinIsAMarkAndSaysSo() throws {
        // GIVEN a task that joined a job after its lookups were done
        var draft = _Draft(duration: 0.5)
        draft.isCoalesced = true
        draft.jobs = [_job(1, .loadImage, from: -0.2, to: 0.4, taskIDs: [2, 1], joinedAt: 0.1, stages: [
            _stage(.memoryLookup, from: -0.2, duration: 0.01) { $0.result = .miss },
            _stage(.download, from: -0.19, duration: 0.5)
        ])]
        let lines = draft.make().formatted(.timeline).split(separator: "\n").map(String.init)

        // THEN
        let lookup = try #require(lines.first { $0.contains("─ memoryLookup ") })
        #expect(lookup.range(of: #"─ memoryLookup +–  +miss · before join$"#, options: .regularExpression) != nil, "Unexpected row: \(lookup)")
        let download = try #require(lines.first { $0.contains("─ download ") })
        #expect(download.hasSuffix("  joined at 290.0 ms of 500.0 ms"), "Unexpected row: \(download)")
        #expect(download.range(of: #"─ download +210\.0 ms"#, options: .regularExpression) != nil, "Unexpected row: \(download)")
    }

    /// A wait is a row of its own when it took a millisecond, or a tenth of
    /// the task. A shorter one is folded into the stage it held up.
    @Test(arguments: [
        (0.1, 0.0005, false), // A fraction of a millisecond of a long task
        (0.1, 0.002, true),   // Over a millisecond
        (0.002, 0.0005, true) // A quarter of a short task
    ] as [(TimeInterval, TimeInterval, Bool)])
    func queueWaitGetsARowWhenItIsWorthOne(duration: TimeInterval, wait: TimeInterval, isRow: Bool) {
        var draft = _Draft(duration: duration)
        draft.jobs = [_job(1, .loadImage, from: 0, to: duration, stages: [
            _stage(.process, queued: 0, from: wait, duration: duration - wait)
        ])]
        let timeline = draft.make().formatted(.timeline)
        #expect(timeline.contains("─ imageProcessingQueue ") == isRow, "Unexpected timeline:\n\(timeline)")
        #expect(timeline.contains("─ process "))
    }

    @Test func everyQueueIsNamedAfterItsConfiguration() {
        let queues: [(ImagePipeline.Diagnostics.Stage.Kind, String)] = [
            (.download, "dataLoadingQueue"), (.decode, "imageDecodingQueue"),
            (.process, "imageProcessingQueue"), (.decompress, "imageDecompressingQueue"),
            (.diskStore, "queue")
        ]
        for (kind, name) in queues {
            var draft = _Draft(duration: 1)
            draft.jobs = [_job(1, .loadImage, from: 0, to: 1, stages: [_stage(kind, queued: 0, from: 0.5, duration: 0.5)])]
            let timeline = draft.make().formatted(.timeline)
            #expect(timeline.contains("├─ \(name) "), "No \(name) in:\n\(timeline)")
        }
    }

    /// A job no chain reaches is a root of its own, and a chain that loops
    /// back on itself prints every job once instead of forever.
    @Test func treeSurvivesJobsThatDontFormAChain() {
        // GIVEN
        var draft = _Draft(duration: 1)
        draft.jobs = [
            _job(1, .loadImage, parent: 2, from: 0, to: 1),
            _job(2, .fetchOriginalImage, parent: 1, from: 0, to: 1),
            _job(3, .fetchOriginalData, parent: 3, from: 0, to: 1),
            _job(4, .loadData, parent: 99, from: 0, to: 1)
        ]

        // WHEN
        let lines = draft.make().formatted(.timeline).split(separator: "\n").map(String.init)

        // THEN
        #expect(lines.filter { $0.contains("j1 ") }.count == 1)
        #expect(lines.filter { $0.contains("j2 ") }.count == 1)
        #expect(lines.contains { $0.hasPrefix("└─ j2 fetchOriginalImage") })
        #expect(lines.contains { $0.hasPrefix("j3 fetchOriginalData") })
        #expect(lines.contains { $0.hasPrefix("j4 loadData") })
        #expect(lines.last?.hasPrefix("total ") == true)
    }

    @Test func processorsAreShortenedToTheirNames() throws {
        // GIVEN
        var draft = _Draft(duration: 1)
        draft.jobs = [
            .init(id: 1, kind: .loadImage, processors: ["com.github.kean/nuke/resize?s=(1.0, 1.0)", "com.example/blur:radius=3", "plain", "trailing/", ""], createdByTaskID: 1, taskIDs: [1], createdAt: _t0, endedAt: _t0 + 1, outcome: .success)
        ]

        // THEN
        let line = try #require(draft.make().formatted(.timeline).split(separator: "\n").first { $0.hasPrefix("j1 ") })
        #expect(line.hasPrefix("j1 loadImage [resize, blur, plain, trailing/, ]"), "Unexpected row: \(line)")
    }

    // MARK: - URLSession

    @Test func requestRowsDescribeTheConnection() throws {
        // GIVEN a redirect over a proxy on a constrained cellular network
        var draft = _Draft(duration: 1)
        let redirect = _transaction(url: "https://cdn.example.com/moved.jpeg", fetchType: .networkLoad, statusCode: 301, responseBytes: 0, isProxy: true, isReused: true, isCellular: true, isExpensive: true, isConstrained: true, from: 0.1)
        let final = _transaction(fetchType: .networkLoad, statusCode: 200, responseBytes: 2_000, from: 0.4)
        draft.jobs = [_job(1, .fetchOriginalData, from: 0, to: 1, stages: [
            _stage(.download, from: 0.05, duration: 0.9) {
                $0.urlSessionTaskID = 3
                $0.urlSessionMetrics = .init(urlSessionTaskID: 3, startedAt: _t0 + 0.05, endedAt: _t0 + 0.95, redirectCount: 1, transactions: [redirect, final])
            }
        ])]
        let metrics = draft.make()
        let lines = metrics.formatted(.all.subtracting(.timestamps)).split(separator: "\n").map(String.init)

        // THEN
        let download = try #require(lines.first { $0.contains("─ download ") })
        #expect(download.hasSuffix("  session #3 · 1 redirect"), "Unexpected row: \(download)")
        let rows = lines.filter { $0.contains("─ networkLoad ") }
        #expect(rows.count == 2)
        #expect(rows[0].hasSuffix("  https://cdn.example.com/moved.jpeg · HTTP 301 · h2 · TLS 1.3 · reused connection · proxy · 10.0.0.1 · sent \(Formatter.bytes(100)) · cellular · expensive · constrained"), "Unexpected row: \(rows[0])")
        // A request to the URL of the task doesn't repeat it
        #expect(rows[1].hasSuffix("  HTTP 200 · h2 · TLS 1.3 · 10.0.0.1 · sent \(Formatter.bytes(100)) · received \(Formatter.bytes(2_000))"), "Unexpected row: \(rows[1])")

        // THEN the steps are listed under their request, a wait in light
        for step in ["domainLookup", "connect", "secureConnection", "request", "waiting", "response"] {
            #expect(lines.filter { $0.contains("─ \(step) ") }.count == 2, "No \(step) in:\n\(lines.joined(separator: "\n"))")
        }
        let waiting = try #require(lines.first { $0.contains("─ waiting ") })
        #expect(waiting.contains("░"), "Unexpected row: \(waiting)")
    }

    @Test func redirectsArePluralized() throws {
        var draft = _Draft(duration: 1)
        draft.jobs = [_job(1, .fetchOriginalData, from: 0, to: 1, stages: [
            _stage(.download, from: 0, duration: 1) {
                $0.urlSessionMetrics = .init(urlSessionTaskID: 3, startedAt: _t0, endedAt: _t0 + 1, redirectCount: 2, transactions: [])
            }
        ])]
        let line = try #require(draft.make().description.split(separator: "\n").first { $0.contains("─ download ") })
        #expect(line.hasSuffix("  2 redirects"), "Unexpected row: \(line)")
    }

    /// A request that ran before the task joined the download keeps its row,
    /// and says why it has no time on it.
    @Test func requestBeforeTheJoinSaysSo() throws {
        // GIVEN a task that joined a download after its redirect was over
        var draft = _Draft(duration: 0.5)
        draft.createdAt = _t0 + 0.5
        draft.startedAt = _t0 + 0.5
        draft.isCoalesced = true
        let redirect = _transaction(url: "https://cdn.example.com/moved.jpeg", fetchType: .networkLoad, statusCode: 301, responseBytes: 0, from: 0.05)
        draft.jobs = [_job(1, .fetchOriginalData, from: 0, to: 0.9, taskIDs: [2, 1], joinedAt: 0.5, stages: [
            _stage(.download, from: 0, duration: 0.9) {
                $0.urlSessionMetrics = .init(urlSessionTaskID: 3, startedAt: _t0, endedAt: _t0 + 0.9, redirectCount: 1, transactions: [redirect])
            }
        ])]

        // THEN
        let lines = draft.make().description.split(separator: "\n").map(String.init)
        let row = try #require(lines.first { $0.contains("─ networkLoad ") })
        #expect(row.hasSuffix(" · before join"), "Unexpected row: \(row)")
        #expect(!lines.contains { $0.contains("─ domainLookup ") })
    }

    // MARK: - Chart

    @Test func chartFillsTheCellsARowCovers() throws {
        // GIVEN rows over the whole task, a quarter of it, and a wait
        var draft = _Draft(duration: 1)
        draft.startedAt = nil
        draft.jobs = [_job(1, .fetchOriginalData, from: 0, to: 1, stages: [
            _stage(.rateLimit, from: 0, duration: 0.25),
            _stage(.download, from: 0.5, duration: 0.25)
        ])]
        let lines = draft.make().formatted([.timeline, .chart]).split(separator: "\n").map(String.init)

        // THEN
        #expect(try _chart(lines, "j1 fetchOriginalData") == String(repeating: "█", count: 20))
        #expect(try _chart(lines, "─ rateLimit ") == String(repeating: "░", count: 5) + String(repeating: " ", count: 15))
        #expect(try _chart(lines, "─ download ") == String(repeating: " ", count: 10) + String(repeating: "█", count: 5) + String(repeating: " ", count: 5))
        #expect(try _chart(lines, "total ") == String(repeating: " ", count: 20))
    }

    /// A row too short for a cell is a point in time: a mark on the left edge
    /// of the cell it starts, or on the right edge of the chart at the end.
    @Test func chartMarksARowTooShortForACell() throws {
        // GIVEN
        var draft = _Draft(duration: 1)
        draft.startedAt = nil
        draft.jobs = [_job(1, .loadImage, from: 0, to: 1, stages: [
            _stage(.memoryLookup, from: 0, duration: 0.001),
            _stage(.diskLookup, from: 0.5, duration: 0.001),
            _stage(.memoryStore, from: 0.999, duration: 0.001)
        ])]
        let lines = draft.make().formatted([.timeline, .chart]).split(separator: "\n").map(String.init)

        // THEN
        #expect(try _chart(lines, "─ memoryLookup ") == "▏" + String(repeating: " ", count: 19))
        #expect(try _chart(lines, "─ diskLookup ") == String(repeating: " ", count: 10) + "▏" + String(repeating: " ", count: 9))
        #expect(try _chart(lines, "─ memoryStore ") == String(repeating: " ", count: 19) + "▕")
    }

    // MARK: - Dates

    @Test func datesAreTheTimestamps() throws {
        // GIVEN
        var draft = _Draft(duration: 1)
        draft.priorityHistory = [.init(at: _t0 + 0.5, priority: .high)]
        draft.jobs = [_job(1, .fetchOriginalData, from: 0, to: 0.9, taskIDs: [2, 1], joinedAt: 0.1, stages: [
            _stage(.download, queued: 0.1, from: 0.2, duration: 0.3) {
                $0.urlSessionMetrics = .init(urlSessionTaskID: 1, startedAt: _t0 + 0.2, endedAt: _t0 + 0.45, redirectCount: 0, transactions: [])
            }
        ])]
        let metrics = draft.make()
        let date = { (offset: TimeInterval) in Date(timeIntervalSince1970: _t0 + offset) }

        // THEN the task
        #expect(metrics.createdDate == date(0))
        #expect(metrics.startedDate == date(0))
        #expect(metrics.endedDate == date(1))
        #expect(metrics.priorityHistory[0].date == date(0.5))

        // THEN the job
        let job = metrics.jobs[0]
        #expect(job.createdDate == date(0))
        #expect(job.endedDate == date(0.9))
        #expect(job.joinedDate == date(0.1))
        #expect(abs(try #require(job.duration) - 0.9) < 1e-9)

        // THEN the stage
        let stage = job.stages[0]
        #expect(stage.queuedDate == date(0.1))
        #expect(stage.startedDate == date(0.2))
        #expect(stage.endedDate == Date(timeIntervalSince1970: try #require(stage.endedAt)))
        #expect(abs(try #require(stage.endedAt) - (_t0 + 0.5)) < 1e-9)
        #expect(abs(try #require(stage.queueWait) - 0.1) < 1e-9)

        // THEN what `URLSession` measured
        let session = try #require(metrics.urlSessionMetrics)
        #expect(session.startedDate == date(0.2))
        #expect(session.endedDate == date(0.45))
        #expect(abs(session.duration - 0.25) < 1e-9)

        // THEN a record that never started and a job that never ended have none
        var never = _Draft(duration: 1)
        never.startedAt = nil
        never.jobs = [_job(1, .loadImage, from: 0, to: nil, outcome: nil, stages: [_stage(.decode, queued: 0, from: nil, duration: nil)])]
        let unfinished = never.make()
        #expect(unfinished.startedDate == nil)
        #expect(unfinished.jobs[0].endedDate == nil)
        #expect(unfinished.jobs[0].joinedDate == nil)
        #expect(unfinished.jobs[0].duration == nil)
        #expect(unfinished.jobs[0].stages[0].startedDate == nil)
        #expect(unfinished.jobs[0].stages[0].endedDate == nil)
        #expect(unfinished.jobs[0].stages[0].queueWait == nil)
    }

    // MARK: - URLSession Summaries

    @Test func urlSessionSummaryCountsOnlyTheNetworkLoads() {
        let metrics = ImagePipeline.Diagnostics.URLSessionMetrics(urlSessionTaskID: 1, startedAt: 0, endedAt: 1, redirectCount: 0, transactions: [
            _transaction(fetchType: .localCache, statusCode: 200, responseBytes: 5_000, from: 0),
            _transaction(fetchType: .networkLoad, statusCode: 304, responseBytes: 300, from: 0.1),
            _transaction(fetchType: .serverPush, statusCode: 200, responseBytes: 7_000, from: 0.2)
        ])
        #expect(metrics.networkBytesReceived == 300)
        #expect(metrics.networkBytesSent == 100)
        #expect(metrics.isServedFromCache)
        #expect(metrics.isRevalidated)

        let empty = ImagePipeline.Diagnostics.URLSessionMetrics(urlSessionTaskID: 1, startedAt: 0, endedAt: 1, redirectCount: 0, transactions: [])
        #expect(empty.networkBytesReceived == 0)
        #expect(!empty.isServedFromCache)
        #expect(!empty.isRevalidated)
    }

    @Test func transactionEndsAtTheLastTimestampItHas() {
        let full = _transaction(fetchType: .networkLoad, statusCode: 200, responseBytes: 0, from: 0.1)
        #expect(full.endedAt == full.responseEndedAt)
        #expect(abs((full.endedAt ?? 0) - (_t0 + 0.1 + 0.25)) < 1e-9)

        // A request that never got a response ends where it stopped
        let cut = ImagePipeline.Diagnostics.URLSessionMetrics.Transaction(url: nil, statusCode: nil, fetchType: .networkLoad, networkProtocol: nil, tlsVersion: nil, remoteAddress: nil, isReusedConnection: false, isProxyConnection: false, isCellular: false, isExpensive: false, isConstrained: false, requestBytes: 0, responseBytes: 0, fetchStartedAt: 5, domainLookupStartedAt: 5, domainLookupEndedAt: 6, connectStartedAt: nil, secureConnectionStartedAt: nil, secureConnectionEndedAt: nil, connectEndedAt: nil, requestStartedAt: nil, requestEndedAt: nil, responseStartedAt: nil, responseEndedAt: nil)
        #expect(cut.endedAt == 6)

        let untimed = _transaction(fetchType: .localCache, statusCode: 200, responseBytes: 0, from: nil)
        #expect(untimed.endedAt == nil)
    }

    // MARK: - Metrics Without a Download

    @Test func recordWithoutAURLSessionDownloadHasNoWireFacts() {
        let metrics = _Draft().make()
        #expect(metrics.urlSessionMetrics == nil)
        #expect(metrics.wireBytes == nil)
        #expect(!metrics.isServedFromHTTPCache)
        #expect(!metrics.isRevalidated)
        #expect(metrics.sharedTaskIDs.isEmpty)
    }

    // MARK: - Names

    @Test func typeNameDropsTheModule() {
        #expect(diagnosticsTypeName(of: ImageDecoders.Default()) == "ImageDecoders.Default")
        #expect(diagnosticsTypeName(of: 1) == "Int")
        #expect(diagnosticsTypeName(of: MockFailingDecoder()) == "MockFailingDecoder")
        // A name that doesn't start with a module is left as is
        #expect(diagnosticsTypeName(of: (1, "a")) == "(Swift.Int, Swift.String)")
    }

    @Test func everyAssetTypeHasAShortName() {
        let types: [AssetType] = [.jpeg, .png, .gif, .heic, .webp, .avif, .bmp, .tiff, .ico, .jpeg2000, .jxl, .mp4, .m4v, .mov]
        for type in types {
            let name = type.diagnosticsName
            #expect(!name.isEmpty)
            #expect(!name.contains("."), "\(name)")
            #expect(name == name.lowercased(), "\(name)")
        }
        #expect(Set(types.map(\.diagnosticsName)).count == types.count)
        #expect(AssetType.jpeg.diagnosticsName == "jpeg")
        #expect(AssetType(rawValue: "com.example.custom").diagnosticsName == "com.example.custom")
    }

    // MARK: - Codable

    /// A record written by a newer schema – new fields, new names – still
    /// opens, with what it doesn't know as `unknown`.
    @Test func recordFromANewerSchemaDecodes() throws {
        // GIVEN
        let json = """
        {
          "schemaVersion": 99,
          "pipelineID": "3B0C6E4A-0000-0000-0000-000000000000",
          "taskID": 7,
          "kind": "video",
          "request": {"processors": [], "options": ["teleport"], "priority": "high"},
          "createdAt": 10,
          "endedAt": 11,
          "duration": 1,
          "outcome": "exploded",
          "source": "carrierPigeon",
          "isCoalesced": false,
          "previewCount": 0,
          "priorityHistory": [],
          "hologram": {"depth": 3},
          "jobs": [{
            "id": 1, "kind": "render", "processors": [], "createdByTaskID": 7, "taskIDs": [7],
            "createdAt": 10, "outcome": "vanished", "priorityHistory": [],
            "stages": [
              {"kind": "memoryLookup", "startedAt": 10, "duration": 0.1, "result": "maybe"},
              {"kind": "download", "startedAt": 10.1, "duration": 0.5, "source": "telepathy", "pixels": [4, 3],
               "urlSessionMetrics": {"urlSessionTaskID": 1, "startedAt": 10.1, "endedAt": 10.6, "redirectCount": 0,
                 "transactions": [{"fetchType": "quantum", "isReusedConnection": false, "isProxyConnection": false,
                   "isCellular": false, "isExpensive": false, "isConstrained": false, "requestBytes": 0, "responseBytes": 0}]}}
            ]
          }]
        }
        """

        // WHEN
        let metrics = try JSONDecoder().decode(ImageTask.Metrics.self, from: Data(json.utf8))

        // THEN
        #expect(metrics.schemaVersion == 99)
        #expect(metrics.kind == .unknown)
        #expect(metrics.outcome == .unknown)
        #expect(metrics.source == .unknown)
        #expect(metrics.request.options == ["teleport"])
        #expect(metrics.request.url == nil)
        #expect(metrics.label == nil)
        #expect(metrics.startedAt == nil)
        let job = try #require(metrics.jobs.first)
        #expect(job.kind == .unknown)
        #expect(job.outcome == .unknown)
        #expect(job.stages[0].result == .unknown)
        #expect(job.stages[1].source == .unknown)
        #expect(job.stages[1].pixels == .init(width: 4, height: 3))
        #expect(job.stages[1].urlSessionMetrics?.transactions.first?.fetchType == .unknown)

        // THEN it still prints
        let description = metrics.description
        #expect(description.hasPrefix("ImageTask #7 · unknown · 1000.0 ms · from unknown\n"), "Unexpected description:\n\(description)")
        #expect(description.contains("\nkind:"))
        #expect(description.contains("j1 unknown"))

        // THEN what it didn't know is written back as `unknown`
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(metrics)) as? [String: Any])
        #expect(object["kind"] as? String == "unknown")
        #expect(object["outcome"] as? String == "unknown")
        #expect(object["hologram"] == nil)
    }

    @Test func pixelSizeIsATwoElementArray() throws {
        let size = ImagePipeline.Diagnostics.PixelSize(width: 640, height: 480)
        #expect(String(data: try JSONEncoder().encode(size), encoding: .utf8) == "[640,480]")
        #expect(try JSONDecoder().decode(ImagePipeline.Diagnostics.PixelSize.self, from: Data("[1,2]".utf8)) == .init(width: 1, height: 2))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ImagePipeline.Diagnostics.PixelSize.self, from: Data("[1]".utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ImagePipeline.Diagnostics.PixelSize.self, from: Data(#"{"width":1,"height":2}"#.utf8))
        }
    }

    @Test func recordWithoutARequiredFieldDoesNotDecode() throws {
        // A record missing its duration isn't a record
        let json = #"{"schemaVersion":2,"pipelineID":"3B0C6E4A-0000-0000-0000-000000000000","taskID":1,"kind":"image","request":{"processors":[],"options":[],"priority":"normal"},"createdAt":1,"endedAt":2,"outcome":"success","isCoalesced":false,"previewCount":0,"priorityHistory":[],"jobs":[]}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ImageTask.Metrics.self, from: Data(json.utf8))
        }
    }

    @Test func handBuiltRecordRoundTrips() throws {
        // GIVEN a record with every optional set
        var draft = _Draft(duration: 1)
        draft.label = "feed"
        draft.error = .init(code: "dataLoadingFailed", description: "x", underlyingDomain: NSURLErrorDomain, underlyingCode: -1001)
        draft.outcome = .failure
        draft.bytes = .init(downloaded: 1, resumed: 2, expected: 3)
        draft.image = .init(width: 1, height: 2, format: "png", isAnimated: true, memoryCost: 8)
        draft.priorityHistory = [.init(at: _t0 + 0.5, priority: .veryHigh)]
        draft.jobs = [_job(1, .fetchOriginalData, from: 0, to: 1, stages: [
            _stage(.download, queued: 0, from: 0.1, duration: 0.5) {
                $0.workDuration = 0.1
                $0.attributedDuration = 0.4
                $0.cacheKey = "00000000"
                $0.isProgressive = false
                $0.decoder = "D"
                $0.processor = "P"
                $0.format = "jpeg"
                $0.pixels = .init(width: 3, height: 4)
                $0.source = .httpCache
                $0.bytes = 5
                $0.resumedBytes = 6
                $0.expectedBytes = 7
                $0.statusCode = 200
                $0.firstByteAt = _t0 + 0.2
                $0.urlSessionTaskID = 9
            }
        ])]
        let metrics = draft.make()

        // WHEN
        let data = try JSONEncoder().encode(metrics)
        let decoded = try JSONDecoder().decode(ImageTask.Metrics.self, from: data)

        // THEN encoding the decoded record gives the same JSON
        let lhs = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        let rhs = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? NSDictionary)
        #expect(lhs == rhs)
        #expect(decoded.description == metrics.description)
        #expect(decoded.jobs[0].stages[0].source == .httpCache)
        #expect(decoded.error?.underlyingCode == -1001)
    }
}

// MARK: - Builders

/// A fixed moment the records are written against.
private let _t0: TimeInterval = 1_000_000

/// A record with sensible defaults: a 100 ms successful image task that
/// waited on nothing.
private struct _Draft {
    var taskID: UInt64 = 1
    var kind: ImageTask.Metrics.Kind = .image
    var label: String?
    var url: String? = "https://example.com/image.jpeg"
    var imageID: String? = "https://example.com/image.jpeg"
    var processors: [String] = []
    var thumbnail: String?
    var options: [String] = []
    var priority: ImageRequest.Priority = .normal
    var createdAt: TimeInterval = _t0
    var startedAt: TimeInterval? = _t0
    var duration: TimeInterval
    var outcome: ImagePipeline.Diagnostics.Outcome = .success
    var error: ImagePipeline.Diagnostics.ErrorSummary?
    var source: ImagePipeline.Diagnostics.Source?
    var isCoalesced = false
    var previewCount = 0
    var priorityHistory: [ImagePipeline.Diagnostics.PriorityChange] = []
    var bytes: ImageTask.Metrics.Bytes?
    var image: ImageTask.Metrics.ImageSummary?
    var jobs: [ImagePipeline.Diagnostics.Job] = []

    init(duration: TimeInterval = 0.1) {
        self.duration = duration
    }

    func make() -> ImageTask.Metrics {
        ImageTask.Metrics(
            schemaVersion: ImagePipeline.Diagnostics.schemaVersion,
            pipelineID: UUID(uuidString: "3B0C6E4A-0000-0000-0000-000000000000")!,
            taskID: taskID,
            kind: kind,
            label: label,
            request: .init(url: url, imageID: imageID, processors: processors, thumbnail: thumbnail, options: options, priority: priority),
            createdAt: createdAt,
            startedAt: startedAt,
            endedAt: createdAt + duration,
            duration: duration,
            outcome: outcome,
            error: error,
            source: source,
            isCoalesced: isCoalesced,
            rootJobID: jobs.first?.id,
            previewCount: previewCount,
            priorityHistory: priorityHistory,
            bytes: bytes,
            image: image,
            jobs: jobs
        )
    }
}

/// A job, with the times in seconds from `_t0`.
private func _job(
    _ id: UInt64,
    _ kind: ImagePipeline.Diagnostics.Job.Kind,
    parent: UInt64? = nil,
    from start: TimeInterval,
    to end: TimeInterval?,
    outcome: ImagePipeline.Diagnostics.Outcome? = .success,
    taskIDs: [UInt64] = [1],
    joinedAt: TimeInterval? = nil,
    stages: [ImagePipeline.Diagnostics.Stage] = []
) -> ImagePipeline.Diagnostics.Job {
    ImagePipeline.Diagnostics.Job(
        id: id,
        kind: kind,
        processors: [],
        parentID: parent,
        createdByTaskID: taskIDs.first ?? 0,
        taskIDs: taskIDs,
        createdAt: _t0 + start,
        endedAt: end.map { _t0 + $0 },
        outcome: outcome,
        joinedAt: joinedAt.map { _t0 + $0 },
        stages: stages
    )
}

/// A stage, with the times in seconds from `_t0`.
private func _stage(
    _ kind: ImagePipeline.Diagnostics.Stage.Kind,
    queued: TimeInterval? = nil,
    from start: TimeInterval?,
    duration: TimeInterval?,
    _ configure: (inout ImagePipeline.Diagnostics.Stage) -> Void = { _ in }
) -> ImagePipeline.Diagnostics.Stage {
    var stage = ImagePipeline.Diagnostics.Stage(kind: kind, queuedAt: queued.map { _t0 + $0 }, startedAt: start.map { _t0 + $0 })
    stage.duration = duration
    configure(&stage)
    return stage
}

/// A request `URLSession` made, starting at `from` seconds past `_t0`, or
/// with no timestamps at all for `nil`: every step of it 10 ms long, except
/// the wait for the response, which is 200 ms.
private func _transaction(
    url: String? = "https://example.com/image.jpeg",
    fetchType: ImagePipeline.Diagnostics.URLSessionMetrics.FetchType,
    statusCode: Int?,
    responseBytes: Int64,
    isProxy: Bool = false,
    isReused: Bool = false,
    isCellular: Bool = false,
    isExpensive: Bool = false,
    isConstrained: Bool = false,
    from start: TimeInterval?
) -> ImagePipeline.Diagnostics.URLSessionMetrics.Transaction {
    let at = { (step: Int) in start.map { _t0 + $0 + Double(step) * 0.01 } }
    return .init(
        url: url,
        statusCode: statusCode,
        fetchType: fetchType,
        networkProtocol: "h2",
        tlsVersion: "TLS 1.3",
        remoteAddress: "10.0.0.1",
        isReusedConnection: isReused,
        isProxyConnection: isProxy,
        isCellular: isCellular,
        isExpensive: isExpensive,
        isConstrained: isConstrained,
        requestBytes: 100,
        responseBytes: responseBytes,
        fetchStartedAt: at(0),
        domainLookupStartedAt: at(0),
        domainLookupEndedAt: at(1),
        connectStartedAt: at(1),
        secureConnectionStartedAt: at(2),
        secureConnectionEndedAt: at(3),
        connectEndedAt: at(3),
        requestStartedAt: at(3),
        requestEndedAt: at(4),
        responseStartedAt: at(4).map { $0 + 0.2 },
        responseEndedAt: at(4).map { $0 + 0.21 }
    )
}

/// The cells of the chart on the first line that contains `needle`: the 20
/// characters past the duration column, with the trimmed spaces put back.
private func _chart(_ lines: [String], _ needle: String) throws -> String {
    let line = try #require(lines.first { $0.contains(needle) }, "No \(needle) in:\n\(lines.joined(separator: "\n"))")
    let value = try #require(line.range(of: #"(–|<0\.1 ms|[0-9.]+ ms)"#, options: .regularExpression))
    let cells = String(line[value.upperBound...].dropFirst(2).prefix(20))
    return cells + String(repeating: " ", count: 20 - cells.count)
}
