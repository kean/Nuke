// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import NukeUI
import SwiftUI

/// Every input the decoders should survive, in a grid, each tile saying what
/// the pipeline made of it: decoded, refused, or crashed, and whether that is
/// what was expected.
///
/// A manual regression sheet: open it on a new OS or after a change to the
/// decoders, and a screenshot of it goes into the release checklist. The
/// inputs are listed in ``DemoZooInput``; the runs, and how a crash is caught,
/// are in ``FixtureZooModel``.
struct FixtureZooDemo: View {
    @State private var model = FixtureZooModel()
    @State private var selection: DemoZooInput?
    @State private var isConfirmingFullDecode = false

    var body: some View {
        List {
            summary
            ForEach(DemoZooInput.Group.allCases, id: \.self) { group in
                Section {
                    grid(group.inputs)
                } header: {
                    Text(group.title)
                }
            }
            links
        }
        // The first time, every input; after a push and back, the ones the
        // push interrupted.
        .task {
            model.runUnfinished()
        }
        .onDisappear {
            model.cancel()
        }
        .sheet(item: $selection) { input in
            FixtureZooDetail(input: input, model: model)
        }
        .demoInfo(Self.info)
    }

    // MARK: Summary

    private var summary: some View {
        let outcomes = model.outcomes.values
        return Section {
            HStack(spacing: 0) {
                FixtureZooCount(outcomes.count(where: { $0.verdict == .decoded }), "decoded", tint: .green)
                FixtureZooCount(outcomes.count(where: { $0.verdict == .refused }), "refused", tint: .blue)
                FixtureZooCount(outcomes.count(where: { $0.verdict == .crashed }), "crashed", tint: .red)
                FixtureZooCount(outcomes.count(where: \.isUnexpected), "unexpected", tint: .orange)
            }
            .padding(.vertical, 4)
            DemoMonoLabel(status, tint: .primary)
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button(runTitle) {
                model.runAll()
            }
            .disabled(model.isRunning)
            Button("Decode the Canvas in Full…") {
                isConfirmingFullDecode = true
            }
            .disabled(model.isRunning)
            // On the button, which an iPad's popover points at.
            .confirmationDialog("Decode in Full?", isPresented: $isConfirmingFullDecode, titleVisibility: .visible) {
                Button("Decode the 20,000 px Canvas", role: .destructive) {
                    model.runRiskyInFull()
                }
            } message: {
                Text("In full, the canvas is a 1.5 GB bitmap, and the app's footprint peaks at about twice that while it's drawn. That is more than an iPhone lets an app have, and the app may be terminated. If it is, the zoo marks the canvas as crashed the next time it opens.")
            }
            if !model.skipped.isEmpty {
                Button("Forget Crashes") {
                    model.forgetCrashes()
                }
                .disabled(model.isRunning)
            }
        } footer: {
            Text("One input at a time, through a pipeline of the zoo's own with no caches, so a run decodes everything again. The 20,000 px canvas is decoded as a 512 px thumbnail unless asked for in full. Tap a tile for its figures.")
        }
    }

    private var status: String {
        if let current = model.current {
            return "decoding \(current.fileName) · \(model.queue.count) to go"
        }
        var parts = ["\(DemoZooInput.allCases.count) inputs"]
        if let run = model.lastRun {
            parts.append(run.mode == .safe ? "safe run" : "full run")
            parts.append(demoDuration(run.duration.demoTimeInterval))
        }
        return parts.joined(separator: " · ")
    }

    /// Why some inputs never reached a decoder, or will not.
    private var warning: String? {
        let notLoaded = model.outcomes.values.count(where: { $0.verdict == .notLoaded })
        let count = notLoaded == 1 ? "1 input" : "\(notLoaded) inputs"
        if let conditions = DemoNetworkConditions.shared.badge {
            return "Network conditions are on (\(conditions)): an input they lose never reaches a decoder, and is not checked." + (notLoaded > 0 ? " \(count) so far." : "")
        }
        return notLoaded > 0 ? "\(count) failed before reaching a decoder, and \(notLoaded == 1 ? "isn't" : "aren't") checked." : nil
    }

    private var runTitle: String {
        let skipped = model.skipped.count
        return skipped == 0 ? "Run All" : "Run All but \(skipped) That Crashed"
    }

    // MARK: Grid

    private func grid(_ inputs: [DemoZooInput]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 152), spacing: 8, alignment: .top)], spacing: 8) {
            ForEach(inputs, id: \.self) { input in
                Button {
                    selection = input
                } label: {
                    FixtureZooTile(input: input, outcome: model.outcomes[input], isDecoding: model.current == input, isQueued: model.queue.contains(input))
                }
                .buttonStyle(.plain)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    }

    private var links: some View {
        Section {
            DemoLink(.imageFormats)
            DemoLink(.animatedImages)
        } header: {
            Text("In the Catalog")
        } footer: {
            Text("Image Formats shows the formats decoded the way an app meets them; Animated Images plays the animations and shows their delays.")
        }
    }

    private static let info = DemoInfo(
        "Fixture Zoo",
        "Inputs the decoders should survive – images at the edges of their formats, damaged files, and files that are not images – each run through a real pipeline and reported as decoded, refused, or crashed, next to what was expected.",
        code: """
        xcrun simctl launch booted com.github.kean.NukeDemo \\
            -demoScreen fixture-zoo
        """,
        points: [
            .init("Inputs", "Six files come from the tests' resources, one is the demo's own HEICS, and the rest are generated on first use: drawn and encoded with Image I/O, cut short, patched, or written byte by byte. Each tile's sheet says which. They are served as fixtures, `demo-fixture://nuke/zoo-…`, so they reach the decoders through a data loader, as a download does."),
            .init("Pipeline", "The zoo's own, with no memory or disk cache and diagnostics on, and the shared decoder registry, so a video goes to `ImageDecoders.Video` as it would anywhere in the app. The decoder, the decode and decompression times, and the memory cost come from each task's `ImageTask.Metrics`."),
            .init("Expected", "A tile is unexpected when it was decoded and should have been refused, or the other way round, or when its size, frame count, or frame delays differ from what the file holds. Damaged files may go either way; they only have to leave the app running. Delays under 11 ms are expected to play as 100 ms."),
            .init("Crashes", "Before each decode, the zoo writes the input's name to `UserDefaults` and synchronizes; after it, it removes it. A name still there when the zoo next opens was being decoded when the app went down, and that tile is marked crashed, with the time. Run All skips a tile that crashed; tap it to run it again."),
            .init("The canvas", "20,000×20,000 pixels in one palette color, 48 KB compressed. A run decodes it as a 512 px thumbnail, which still takes the footprint about 390 MB up inside Image I/O, and nearly two seconds on the simulator. In full, it is a 1.5 GB bitmap, and the footprint peaks about 3 GB up while it's drawn: enough to have an iPhone terminate the app. The simulator has no such limit."),
            .init("Figures", "A tile's first line is the size with the orientation applied, the type the pipeline detected, and the frames; the second, the time spent decoding and decompressing, and what the image costs in memory. Image I/O decodes most stills lazily, so for them most of the time is in decompression. The sheet behind a tile has the rest, and what Image I/O reads in the file's header."),
            .init("Not loaded", "An input that failed before it reached a decoder – a fixture that couldn't be made, or a download the network conditions lost – is counted apart, and is neither expected nor unexpected.")
        ]
    )
}

// MARK: - Tile

/// One input: a preview, the verdict, two lines of figures, and the
/// expectation.
private struct FixtureZooTile: View {
    let input: DemoZooInput
    let outcome: FixtureZooModel.Outcome?
    let isDecoding: Bool
    let isQueued: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            FixtureZooPreview(outcome: outcome, isDecoding: isDecoding)
                .frame(height: 76)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(input.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                if let outcome {
                    FixtureZooBadge(verdict: outcome.verdict)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .truncationMode(.middle)
            expectation
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(outcome?.isUnexpected == true ? Color.orange : Color.secondary.opacity(0.25), lineWidth: outcome?.isUnexpected == true ? 1.5 : 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Two lines: what came out, and what it cost; or the error.
    private var lines: [String] {
        guard let outcome else {
            return [input.fileName, isDecoding ? "decoding…" : isQueued ? "waiting" : "not run"]
        }
        switch outcome.verdict {
        case .decoded:
            guard let image = outcome.image else { return ["", ""] }
            let frames = image.frameCount > 1 ? "\(image.frameCount) frames" : "still"
            // Image I/O decodes a still when it's first drawn, which is in
            // decompression.
            let work = [outcome.decodeDuration, outcome.decompressDuration].compactMap { $0 }
            let decode = work.isEmpty ? "–" : demoTime(work.reduce(0, +))
            let cost = image.memoryCost.map { demoByteCount($0) } ?? "–"
            return [
                "\(image.width)×\(image.height) · \(image.type ?? "?") · \(frames)",
                "\(decode) · \(cost)"
            ]
        case .refused, .notLoaded:
            return [outcome.error ?? "failed", outcome.errorDetail ?? input.fileName]
        case .crashed:
            return ["went down decoding", "\(outcome.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())) · \(outcome.variant.title)"]
        }
    }

    /// Whether the outcome is the expected one, and if not, why. Two lines
    /// high whatever it says, so the tiles of a row line up.
    private var expectation: some View {
        let expected = input.expectation
        let (symbol, text, style): (String, String, AnyShapeStyle) = if let outcome, let mismatch = outcome.mismatch {
            ("xmark.circle.fill", mismatch, AnyShapeStyle(.orange))
        } else if outcome?.verdict == .notLoaded {
            ("minus.circle", "not checked", AnyShapeStyle(.tertiary))
        } else if outcome != nil {
            ("checkmark.circle", expected.outcome == .either ? "survived" : "as expected", AnyShapeStyle(.secondary))
        } else {
            ("circle.dashed", "expects \(expected.summary)", AnyShapeStyle(.tertiary))
        }
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: symbol)
            Text(text)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption2.weight(outcome?.isUnexpected == true ? .medium : .regular))
        .foregroundStyle(style)
    }
}

/// The image as the pipeline returned it, playing if it animates, or a
/// symbol for what happened instead.
private struct FixtureZooPreview: View {
    let outcome: FixtureZooModel.Outcome?
    let isDecoding: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.fill.tertiary)
            content
                .padding(4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var content: some View {
        if let outcome {
            switch outcome.verdict {
            case .decoded:
                if let container = outcome.container {
                    FixtureZooImage(container: container)
                } else if let image = outcome.image {
                    Text("\(image.width)×\(image.height)\nnot drawn")
                        .font(.system(.caption2, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            case .refused:
                symbol("nosign", .blue)
            case .notLoaded:
                symbol("icloud.slash", .secondary)
            case .crashed:
                symbol("bolt.trianglebadge.exclamationmark.fill", .red)
            }
        } else if isDecoding {
            ProgressView()
        }
    }

    private func symbol(_ name: String, _ style: some ShapeStyle) -> some View {
        Image(systemName: name)
            .font(.title2)
            .foregroundStyle(style)
    }
}

/// A decoded image: the animation if there is one, the still otherwise, with
/// the pixels of a tiny one left sharp.
private struct FixtureZooImage: View {
    let container: ImageContainer

    var body: some View {
        let image = container.image
        let pixels = max(image.size.width, image.size.height) * image.scale
        if image.size.width < 1 || image.size.height < 1 {
            Text("empty image")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.orange)
        } else if let animation = AnimatedImage(container: container) {
            animation
                .resizable()
                .scaledToFit()
        } else {
            Image(demoPlatformImage: image)
                .resizable()
                .interpolation(pixels < 64 ? .none : .medium)
                .scaledToFit()
        }
    }
}

private struct FixtureZooBadge: View {
    let verdict: FixtureZooModel.Outcome.Verdict

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
            .fixedSize()
    }

    private var title: String {
        switch verdict {
        case .decoded: "decoded"
        case .refused: "refused"
        case .notLoaded: "not loaded"
        case .crashed: "crashed"
        }
    }

    private var tint: Color {
        switch verdict {
        case .decoded: .green
        case .refused: .blue
        case .notLoaded: .gray
        case .crashed: .red
        }
    }
}

/// A count in the summary: the number over what it counts.
private struct FixtureZooCount: View {
    let count: Int
    let title: String
    let tint: Color

    init(_ count: Int, _ title: String, tint: Color) {
        self.count = count
        self.title = title
        self.tint = tint
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .foregroundStyle(count > 0 ? tint : .secondary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Detail

/// Everything known about one input, and the runs it can be given.
private struct FixtureZooDetail: View {
    let input: DemoZooInput
    let model: FixtureZooModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let outcome = model.outcomes[input]
        NavigationStack {
            List {
                Section {
                    FixtureZooPreview(outcome: outcome, isDecoding: model.current == input)
                        .frame(height: 140)
                        .listRowInsets(EdgeInsets())
                }
                if let outcome {
                    Section {
                        results(outcome)
                    } header: {
                        Text("Result")
                    }
                }
                Section {
                    Text(input.summary)
                    row("File", "zoo-\(input.fileName)")
                    row("Served as", input.mimeType)
                    row("Expected", input.expectation.summary)
                    if let file = outcome?.file {
                        fileRows(file)
                    }
                } header: {
                    Text("Input")
                } footer: {
                    Text("Image I/O and Header are what Image I/O reads in the file before any decoder sees it.")
                }
                Section {
                    Button("Run Again") {
                        model.run(input)
                    }
                    if input.safeMaxPixelSize != nil {
                        Button("Decode in Full", role: .destructive) {
                            model.run(input, mode: .full)
                        }
                    }
                }
                .disabled(model.isRunning)
            }
            .navigationTitle(input.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func fileRows(_ file: DemoImageHeader) -> some View {
        row("Image I/O", file.typeSummary)
        if let pixels = file.pixelSummary {
            row("Header", pixels)
        }
        if let profile = file.profile {
            row("Profile", profile)
        }
    }

    @ViewBuilder
    private func results(_ outcome: FixtureZooModel.Outcome) -> some View {
        row("Verdict", outcome.verdict == .notLoaded ? "not loaded" : "\(outcome.verdict)", tint: outcome.isUnexpected ? .orange : nil)
        if let mismatch = outcome.mismatch {
            row("Unexpected", mismatch, tint: .orange)
        }
        row("Decoded as", outcome.variant.title)
        if let error = outcome.error {
            row("Error", error)
        }
        if let detail = outcome.errorDetail {
            row("Detail", detail)
        }
        if let image = outcome.image {
            row("Size", "\(image.width)×\(image.height)" + (image.bitmapSize.map { " · bitmap \($0.width)×\($0.height)" } ?? ""))
            if let orientation = image.orientation {
                row("Orientation", orientation)
            }
            row("Type", image.type ?? "unknown")
            row("Bitmap", [image.bitsPerComponent.map { "\($0) bpc" }, image.colorModel].compactMap { $0 }.joined(separator: " · "))
            if image.frameCount > 1 {
                row("Frames", "\(image.frameCount) · \(demoDelayList(image.delays))")
                row("Loops", image.loopCount.map { $0 == 0 ? "forever" : "\($0)" } ?? "–")
            } else {
                row("Frames", image.hasData ? "a still, data kept" : "a still")
            }
            row("Memory", image.memoryCost.map { demoByteCount($0) } ?? "–")
        }
        if let decoder = outcome.decoder {
            row("Decoder", decoder)
        }
        if let decode = outcome.decodeDuration {
            row("Decode", demoTime(decode))
        }
        if let decompress = outcome.decompressDuration {
            row("Decompress", demoTime(decompress))
        }
        if let duration = outcome.duration {
            row("Task", demoTime(duration))
        }
        if let bytes = outcome.byteCount {
            row("Data", bytes == 0 ? "0 bytes" : demoByteCount(bytes))
        }
        if outcome.verdict != .crashed {
            row("Footprint peak", outcome.peakFootprintIncrease.map { "+\(demoByteCount($0))" } ?? "no new high over 16 MB")
        }
        row(outcome.verdict == .crashed ? "Started" : "At", outcome.date.formatted(date: .abbreviated, time: .standard))
    }

    private func row(_ title: String, _ value: String, tint: Color? = nil) -> some View {
        LabeledContent(title) {
            DemoMonoLabel(value, tint: tint)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Helpers

extension Image {
    /// An image of the platform's own type.
    fileprivate init(demoPlatformImage image: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: image)
        #else
        self.init(nsImage: image)
        #endif
    }
}

/// Milliseconds with a decimal under a second, seconds above it.
private func demoTime(_ value: TimeInterval) -> String {
    value < 1 ? demoMilliseconds(value) : demoSeconds(value)
}

extension DemoZooInput: Identifiable {
    var id: String { rawValue }
}
