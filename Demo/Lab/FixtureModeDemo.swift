// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI

/// The switch that takes the demo offline, and the fixtures it serves then:
/// what each one is, its size, how long it took to make, and a digest to tell
/// whether a run is on the same bytes as the last one.
///
/// The screen reads ``DemoFixtureStore`` twice a second, the way the other
/// instruments sample, rather than being told of every fixture made.
struct FixtureModeDemo: View {
    @State private var records: [DemoFixture: DemoFixtureStore.Record] = [:]
    @State private var isMaking = false

    private let store = DemoFixtureStore.shared

    var body: some View {
        List {
            mode
            fixtures
            photos
            actions
            links
        }
        .task {
            while !Task.isCancelled {
                records = store.records
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        .demoInfo(Self.info)
    }

    // MARK: Sections

    private var mode: some View {
        @Bindable var mode = DemoFixtureMode.shared
        return Section {
            Toggle("Offline", isOn: $mode.isOffline)
            if DemoLaunchOptions.current.isDeterministic {
                LabeledContent("Launched with") {
                    DemoMonoLabel("-demoDeterministic 1")
                }
            }
        } footer: {
            Text("Offline, every download of every pipeline is one of the fixtures below, and nothing goes to the network. Screens opened from now on load fixture URLs; a screen already open keeps its own. Lab screens start on fixtures either way.")
        }
    }

    private var fixtures: some View {
        Section {
            ForEach(DemoFixture.named, id: \.self) { fixture in
                FixtureRow(
                    name: fixture.name,
                    summary: "\(fixture.summary) · \(fixture.standsInFor)",
                    size: records[fixture].map { demoByteCount($0.byteCount) },
                    figures: figures(for: fixture)
                )
            }
        } header: {
            Text("Fixtures")
        } footer: {
            Text("Made the first time a load asks for one, and kept in memory. The digest is the start of the SHA-256 of the data: the same on every run on this system.")
        }
    }

    private var photos: some View {
        let fixtures = DemoFixture.photos
        let made = fixtures.compactMap { records[$0] }
        let byteCount = made.reduce(0) { $0 + $1.byteCount }
        let durations = made.map(\.duration)
        let average = durations.isEmpty ? Duration.zero : durations.reduce(.zero, +) / durations.count
        return Section {
            FixtureRow(
                name: "photo-0 … photo-\(fixtures.count - 1).jpeg",
                summary: "360×240 JPEG, every third one 240×360 · each stands in for a photo of the stream",
                size: made.isEmpty ? nil : demoByteCount(byteCount),
                figures: made.isEmpty
                    ? "not made yet"
                    : "\(made.count) of \(fixtures.count) made · \(average.milliseconds) avg · \((durations.max() ?? .zero).milliseconds) max"
            )
        } header: {
            Text("Photos")
        }
    }

    private var actions: some View {
        Section {
            Button("Make All") {
                make(again: false)
            }
            Button("Make All Again") {
                make(again: true)
            }
        } footer: {
            Text("Making them again times the drawing and encoding on this device. A load in flight keeps the data it has.")
        }
        .disabled(isMaking)
    }

    private var links: some View {
        Section {
            DemoLink(.progressiveDecoding)
            DemoLink(.imageFormats)
            DemoLink(.scrollStress)
        } header: {
            Text("Try It On")
        } footer: {
            Text("Offline, Progressive Decoding shows all ten scans of its JPEG, one at a time. Scroll Stress runs on fixtures unless it's told otherwise.")
        }
    }

    // MARK: Helpers

    private func figures(for fixture: DemoFixture) -> String {
        if fixture == .missing {
            return "no data: fails before the first byte"
        }
        guard let record = records[fixture] else {
            return "not made yet"
        }
        var parts = [record.isBundled ? "read in \(record.duration.milliseconds)" : "made in \(record.duration.milliseconds)"]
        if record.scanOffsets.count > 1 {
            parts.append("\(record.scanOffsets.count) scans")
        }
        parts.append(record.digest)
        return parts.joined(separator: " · ")
    }

    private func make(again: Bool) {
        isMaking = true
        Task {
            if again {
                store.removeAll()
                records = [:]
            }
            await store.makeAll()
            records = store.records
            isMaking = false
        }
    }

    private static let info = DemoInfo(
        "Fixture Mode",
        "Offline, the demo serves every image from fixtures – pictures drawn and encoded the first time a load asks for them, and a few bundled files – so a run measures the pipeline rather than the network, and looks the same as the last one.",
        code: """
        xcrun simctl launch booted com.github.kean.NukeDemo \\
            -demoFixtures offline -demoScreen uikit-views
        """,
        points: [
            .init("Routing", "The delegate of every demo pipeline sends a request for a fixture URL, and every request while offline, to a fixture loader rather than the loader the pipeline was configured with. It reads the switch for every download, so switching needs no new pipeline."),
            .init("URLs", "A fixture's URL looks like `demo-fixture://nuke/photo-12.jpeg`, and only the fixture loader answers one. Offline, the screens opened next load them, so their caches keep fixtures apart from photos. A network URL with no fixture to stand in for it fails, and Console says which, under the `Fixtures` category."),
            .init("Pace", "A pipeline gets a fixture in one chunk, at once, unless its loader says otherwise. Progressive Decoding's throttled loader sets the byte rate, and the progressive JPEG comes a scan per chunk, each a little after the pipeline is ready to decode the next preview, so every scan is shown, in about six seconds. Scroll Stress waits 50 ms before each fixture."),
            .init("Cancellation", "A cancelled fixture load calls `completion` once, with `URLError.cancelled`, as `DataLoader` does. The pipeline frees a data loading slot only when a loader completes."),
            .init("Deterministic", "`-demoDeterministic 1` starts the app offline, with the disk caches emptied, no fade on UIKit image views, and counted tokens instead of random ones. Timings, animation frames, and the HUD's figures still vary."),
            .init("The same bytes", "Drawing and encoding depend on nothing but the fixture, so the digests hold from one run to the next on one system. Another OS version may encode differently.")
        ]
    )
}

/// A fixture: its name and size, what it is, and what making it took.
private struct FixtureRow: View {
    let name: String
    let summary: String
    let size: String?
    let figures: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.system(.subheadline, design: .monospaced))
                Spacer(minLength: 12)
                DemoMonoLabel(size ?? "–", tint: .primary)
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            DemoMonoLabel(figures)
        }
    }
}

extension Duration {
    /// In milliseconds, the way the demo writes them: `18.4ms`.
    fileprivate var milliseconds: String {
        demoMilliseconds(Double(components.seconds) + Double(components.attoseconds) / 1e18)
    }
}
