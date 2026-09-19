// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// Every task of a burst and where it is, and the five task queues of its
/// pipeline, sampled ten times a second. The burst is in
/// ``ConcurrencyInspectorModel``.
struct ConcurrencyInspectorDemo: View {
    @State private var model = ConcurrencyInspectorModel()

    var body: some View {
        List {
            tasks
            queues
        }
        .task {
            if DemoLaunchOptions.claimAutorun(for: .concurrencyInspector) {
                model.start()
            }
            while !Task.isCancelled {
                model.sample()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .onDisappear {
            model.leave()
        }
        .demoInfo(Self.info)
    }

    // MARK: Tasks

    private var tasks: some View {
        Section {
            HStack(spacing: 10) {
                Button("Start") {
                    model.start()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunning)
                Button("Cancel All", role: .destructive) {
                    model.cancelAll()
                }
                .buttonStyle(.bordered)
                .disabled(!model.isRunning)
                Spacer(minLength: 0)
                if !model.stages.isEmpty {
                    let finished = model.stages.count(where: \.isFinished)
                    DemoMonoLabel("\(finished)/\(model.stages.count) · \(demoSeconds(model.elapsed))", tint: .primary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                InspectorTaskMap(stages: model.stages)
                legend
            }
            .padding(.vertical, 4)
        } header: {
            Text("Tasks")
        } footer: {
            Text("\(ConcurrencyInspectorModel.burstCount) requests at once – photos, photos resized and blurred, and thumbnails of a 12 MP JPEG – on a pipeline of the screen's own, with no memory cache and fixtures that take 0.3 s each. A square per task, in the order they were created.")
        }
    }

    /// The tasks in each stage, in the order a task goes through them.
    private var legend: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 4) {
            ForEach(InspectorStage.allCases, id: \.self) { stage in
                let count = model.stages.count { $0 == stage }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(stage.color)
                        .frame(width: 9, height: 9)
                    Text(verbatim: "\(demoPad(count.formatted(), to: 3)) \(stage.title)")
                        .foregroundStyle(count > 0 ? .primary : .secondary)
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
    }

    // MARK: Queues

    private var queues: some View {
        Section {
            ForEach(model.queues) { status in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(status.title)
                            .font(.subheadline)
                        HStack(spacing: 8) {
                            slots(status)
                            DemoMonoLabel("\(status.running)/\(status.limit) running" + (status.isSuspended ? " · suspended" : ""), tint: status.isSuspended ? .orange : .primary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button(status.isSuspended ? "Resume" : "Suspend") {
                        model.toggleSuspended(status)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Queues")
        } footer: {
            Text("The work running on each queue against its limit, as the probe counts it, and as the screen's processor does for processing, which the probe can't see. Suspend a queue mid-burst and the tasks gather in front of it.")
        }
    }

    /// A square per slot, filled while work runs in it.
    private func slots(_ status: ConcurrencyInspectorModel.QueueStatus) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<status.limit, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < status.running ? (status.isSuspended ? Color.orange : .accentColor) : Color.primary.opacity(0.12))
                    .frame(width: 7, height: 10)
            }
        }
    }

    // MARK: Info

    private static let info = DemoInfo(
        "Concurrency Inspector",
        "Starts a burst of requests on a pipeline of its own and shows, ten times a second, where every task is and what each of the five task queues runs. A change to how the pipeline schedules its work shows here first.",
        points: [
            .init("The requests", "Photos, decoded on the pipeline's actor as their data arrives and then decompressed; photos resized and blurred on the processing queue; and 480 px thumbnails of the 12 MP JPEG, decoded on the decoding queue. The disk cache keeps nothing, so the pipeline encodes the blurred photos and thumbnails for it, after their tasks finish, and writes no file."),
            .init("Where a task is", "Waiting until its download starts, for a data loading slot or the rate limiter; loading until the last byte; then decoding, processing, and decompressing as its request needs, each with the wait for its queue; then finished. The pipeline's delegate and the probe's reports of the calls to the loader say when a task moves on."),
            .init("Queues", "`TaskQueue` makes its limit and suspension public and keeps what waits to itself. Suspending a queue lets what runs finish and starts nothing more, for the next burst too; the screen resumes every queue when it closes."),
            .init("-demoAutorun 1", "Starts a burst as soon as the screen opens, once per launch.")
        ]
    )
}

extension InspectorStage {
    var color: Color {
        switch self {
        case .waiting: .gray.opacity(0.4)
        case .loading: .blue
        case .decoding: .purple
        case .processing: .orange
        case .decompressing: .teal
        case .image: .green
        case .cancelled: .yellow
        case .failed: .red
        }
    }
}

/// A square per task, drawn in one pass, with room for a whole burst.
private struct InspectorTaskMap: View {
    let stages: [InspectorStage]

    private static let columns = 30

    var body: some View {
        let count = max(stages.count, ConcurrencyInspectorModel.burstCount)
        let rows = (count + Self.columns - 1) / Self.columns
        Canvas { context, size in
            let pitch = size.width / CGFloat(Self.columns)
            for index in 0..<count {
                let rect = CGRect(x: CGFloat(index % Self.columns) * pitch, y: CGFloat(index / Self.columns) * pitch, width: pitch - 2, height: pitch - 2)
                let color = index < stages.count ? stages[index].color : .primary.opacity(0.08)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
            }
        }
        .aspectRatio(CGFloat(Self.columns) / CGFloat(rows), contentMode: .fit)
        .accessibilityHidden(true)
    }
}
