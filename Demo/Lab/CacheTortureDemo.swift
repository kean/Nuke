// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// Hammers `DataCache` and `ImageCache` from many threads at once, then
/// reports whether they kept their limits and returned what was written, as
/// a list of verdicts.
///
/// The runs are in ``CacheTortureModel``: ``DataCacheTorture`` for the disk
/// cache, ``ImageCacheTorture`` for the memory cache.
struct CacheTortureDemo: View {
    @State private var model = CacheTortureModel()
    @State private var showsDetails = false
    @State private var showsLog = false

    var body: some View {
        List {
            controls
            dataCache
            if let report = model.imageReport {
                imageCache(report)
            }
            if !model.isRunning, model.dataReport != nil {
                log
            }
            links
        }
        .task {
            guard DemoLaunchOptions.current.autoruns, !Autorun.hasRun else { return }
            Autorun.hasRun = true
            model.run()
        }
        .onDisappear {
            model.stop()
        }
        .demoInfo(Self.info)
    }

    // MARK: Controls

    private var controls: some View {
        @Bindable var model = model
        return Section {
            HStack(spacing: 12) {
                if model.isRunning {
                    Button("Stop", role: .destructive) {
                        model.stop()
                    }
                    .buttonStyle(.bordered)
                    ProgressView()
                } else {
                    Button("Run") {
                        model.run()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Picker("Duration", selection: $model.seconds) {
                    ForEach(CacheTortureModel.durations, id: \.self) { seconds in
                        Text("for \(seconds) s").tag(seconds)
                    }
                }
                .labelsHidden()
                .disabled(model.isRunning)
                Spacer()
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            DemoMonoLabel(status, tint: .primary)
        } footer: {
            Text("A `DataCache` of 2 MB that sweeps every second, hammered by a dozen tasks, then an `ImageCache` hammered by eight threads. Each run has caches of its own, in a directory of its own, removed at the end.")
        }
    }

    private var status: String {
        switch model.status {
        case .idle:
            let verdicts = (model.dataReport?.verdicts ?? []) + (model.imageReport?.verdicts ?? [])
            guard let report = model.dataReport, !verdicts.isEmpty else {
                return "not run yet"
            }
            return "run \(report.number) · " + verdicts.demoSummary
        case let .hammering(elapsed, total):
            return "hammering DataCache · \(demoSeconds(min(elapsed, total))) of \(demoSeconds(total))"
        case .checking(let step):
            return "checking: \(step)"
        }
    }

    // MARK: DataCache

    private var dataCache: some View {
        Section {
            if model.isRunning, !model.liveSamples.isEmpty {
                chart(samples: model.liveSamples, sweeps: model.liveSweeps, seconds: model.seconds, isLive: true)
            } else if let report = model.dataReport {
                chart(samples: report.samples, sweeps: report.manualSweeps.map(\.endedAt) + report.scheduledSweeps, seconds: report.seconds, isLive: false)
            }
            if let report = model.dataReport, !model.isRunning {
                ForEach(report.verdicts) { verdict in
                    DemoVerdictRow(verdict, showsDetail: showsDetails)
                }
            } else if !model.isRunning {
                Text("Run writes, reads, and removes entries from twelve tasks at once while the cache sweeps, then checks its size, its sweeps, its flushes, and every read.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                if let report = model.dataReport, !model.isRunning {
                    Text("DataCache · Run \(report.number) · \(report.seconds) s")
                } else {
                    Text("DataCache")
                }
                Spacer()
                if model.dataReport != nil, !model.isRunning {
                    detailsButton
                }
            }
        } footer: {
            Text("The size of the files on disk, sampled every 100 ms, against the 2 MB limit. Orange ticks are sweeps: `sweep()` calls for the first 4 s, then the cache's own.")
        }
    }

    private func chart(samples: [DemoSparkline.Sample], sweeps: [TimeInterval], seconds: Int, isLive: Bool) -> some View {
        let limit = Double(DataCacheTorture.sizeLimit)
        let highest = samples.map(\.value).max() ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            DemoSparkline(
                samples: samples,
                rules: [.init(value: limit, label: "sizeLimit \(demoByteCount(DataCacheTorture.sizeLimit))", color: .orange)],
                ticks: sweeps,
                duration: TimeInterval(seconds),
                range: 0...max(limit * 1.5, highest * 1.1)
            )
            .frame(height: 96)
            DemoMonoLabel("\(isLive ? "now" : "last") \(demoByteCount(Int(samples.last?.value ?? 0))) · highest \(demoByteCount(Int(highest))) · \(sweeps.count) sweeps")
        }
        .padding(.vertical, 4)
    }

    private var detailsButton: some View {
        Button(showsDetails ? "Hide Details" : "Details") {
            showsDetails.toggle()
        }
        .font(.footnote)
        .textCase(nil)
    }

    // MARK: ImageCache

    private func imageCache(_ report: ImageCacheTorture.Report) -> some View {
        Section {
            ForEach(report.verdicts) { verdict in
                DemoVerdictRow(verdict, showsDetail: showsDetails, note: verdict.state == .expectedFailure ? "expected · Nuke issue" : nil)
            }
        } header: {
            HStack {
                Text("ImageCache")
                Spacer()
                if model.dataReport == nil {
                    detailsButton
                }
            }
        } footer: {
            Text("Caches of their own, with entries of known cost: a one-pixel image and a buffer of data, which `ImageCache` charges for too.")
        }
    }

    // MARK: Log

    private var log: some View {
        Section {
            DisclosureGroup("Run Log", isExpanded: $showsLog) {
                if let report = model.dataReport {
                    ForEach(report.log) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            DemoMonoLabel(demoPad(String(format: "%.2f", line.time), to: 6))
                            Text(line.text)
                                .font(.caption)
                        }
                    }
                }
                if let report = model.imageReport {
                    ForEach(Array(report.log.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            DemoMonoLabel(demoPad("image", to: 6))
                            Text(line)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var links: some View {
        Section {
            DemoLink(.caching)
        } header: {
            Text("In the Catalog")
        } footer: {
            Text("Caching shows what the memory cache and each `DataCachePolicy` keep, and the calls that read and write them.")
        }
    }

    private static let info = DemoInfo(
        "Cache Torture",
        "Hammers the two caches Nuke ships – `DataCache` on disk and `ImageCache` in memory – from many threads at once, then checks their limits, their sweeps and trims, and that every read returned what was written. Pass or fail, with the numbers.",
        code: """
        xcrun simctl launch booted com.github.kean.NukeDemo \\
            -demoScreen cache-torture -demoAutorun 1
        """,
        points: [
            .init("The DataCache", "A new cache in a directory of its own, with `sizeLimit` at 2 MB and `sweepInterval` at a second. Eight writers each own 40 keys: they store entries of 2–32 KB, read them back, remove some, and ask `containsData`, a hundred times a second each. Four scanners read any key. A task awaits `flush()` every 100 ms, and another `sweep()` four times in the first 4 s."),
            .init("Sweeps", "The limit is enforced when the cache sweeps, down to 70% of it, not on each write, so a cache written this fast goes over it between sweeps. The cache sweeps on its own for the first time 5 s after it's created, whatever `sweepInterval` says; the run calls `sweep()` until then. Nothing public reports a scheduled sweep, so the run reads the date the cache writes into its directory after each one."),
            .init("Reads", "Every entry carries its key, a version, its length, and a checksum. A writer is the only one to touch its keys, so a read must return its last write, or nothing once it removed the key or a sweep took the entry. A stale version, another key's entry, a torn one, or an entry back after its removal is a failure."),
            .init("flush()", "It writes the staged changes itself instead of waiting for the automatic drain a second after a change, so no call should take a second. It can wait behind a sweep or a drain already on the cache's one I/O queue."),
            .init("removeAll()", "Every key reads nothing as soon as it returns, and an entry written right after it survives the drain that empties the directory."),
            .init("The ImageCache", "Caches of their own, with entries of a known cost: a one-pixel image and a buffer of data, which `ImageCache` charges for. `ttl` hides an entry once it expires, but only a lookup or an eviction frees it. `entryCostLimit` refuses an entry of a tenth of the limit or more. Eight threads insert 5,000 entries each while others read, trim, and empty the cache, and no reading of `totalCost` or `totalCount` may find it over a limit."),
            .init("A refused image", "The one expected failure. An image too big for `entryCostLimit`, stored under a key that already holds a smaller one, is refused and leaves the smaller one in place, so the cache returns the image the app replaced."),
            .init("-demoAutorun 1", "Runs everything as soon as the screen opens, once per launch, so a script can take a screenshot of the verdicts.")
        ]
    )
}

/// Runs on its own only once per launch, not each time the screen comes
/// back.
@MainActor
private enum Autorun {
    static var hasRun = false
}
