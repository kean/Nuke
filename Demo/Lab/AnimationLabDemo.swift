// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// A wall of up to 36 animations drawing from one frame pool, with the knobs
/// that push it and the figures that say what it did: a pool down to 4 MB,
/// player budgets under a megabyte, frame transforms, copies in and out of
/// lockstep, zoom to 800%, a memory warning, power throttling, and a soak that
/// plays for an hour.
///
/// It reports numbers, and leaves explaining them to **Animated Images** in the
/// catalog, which does it for one animation. The formats are fixtures unless
/// the source says otherwise, so that a run compares with the last one.
struct AnimationLabDemo: View {
    @State private var model = AnimationLabModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        AnimationLabStage(model: model)
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                model.startWatching()
                defer { model.stopWatching() }
                await demoWaitUntilCancelled()
            }
            .task {
                guard DemoLaunchOptions.current.autoruns, !Autorun.hasRun else { return }
                Autorun.hasRun = true
                while model.isLoading {
                    guard (try? await Task.sleep(for: .milliseconds(100))) != nil else { return }
                }
                model.startSoak()
            }
            .onAppear {
                model.displayScale = displayScale
                model.appear()
            }
            .onDisappear {
                model.disappear()
            }
            .onChange(of: displayScale) {
                model.displayScale = displayScale
            }
            // Before `demoConsole`, which scopes them to the stage.
            .navigationTitle("Animation Lab")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CountMenu(count: $model.count, current: model.count)
                        .equatable()
                }
            }
            .demoConsole(collapsedHeight: Self.collapsedConsoleHeight, info: Self.info) {
                AnimationLabConsole(model: model)
            }
    }

    /// Tall enough for the pool meter and a first row under it, which is what
    /// says there is more to pull up.
    private static let collapsedConsoleHeight: CGFloat = 208

    /// How many animations are on the wall, in the title bar, where it is
    /// reachable whatever the console is doing.
    ///
    /// Equatable for the reason the **Animated Images** menus are: a menu
    /// rebuilt while it is open drops its items.
    private struct CountMenu: View, Equatable {
        @Binding var count: Int
        /// The count as a plain value: the comparison runs outside the main
        /// actor, where a binding can't be read and a constant can.
        let current: Int

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.current == rhs.current
        }

        var body: some View {
            Menu {
                ForEach(AnimationLabModel.counts, id: \.self) { choice in
                    Toggle(isOn: Binding(get: { count == choice }, set: { _ in count = choice })) {
                        Text(demoCount(choice, "animation"))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(current)")
                        .monospacedDigit()
                    Image(systemName: "square.grid.2x2")
                        .imageScale(.small)
                }
            }
            .accessibilityLabel("Number of animations")
        }
    }

    fileprivate static let info = DemoInfo(
        "Animation Lab",
        "Up to 36 animations drawing their frames from one `AnimatedImageFramePool`, with the settings that push it past sensible values and the figures that show what it did. **Animated Images** in the catalog says what the buffer map and the figures mean.",
        points: [
            .init("Wall", "The count is in the title bar. Cells keep their players when it changes: new ones are added at the end and join the ones playing. Formats plays a GIF, an APNG, a WebP, a HEIC, and a long GIF; Delays plays the Fixture Zoo's animations with zero, mixed, and unclamped delays, and one that counts eight frames and has one. The formats are fixtures unless Source says Network. Every player repeats forever."),
            .init("Frame pool", "The budget is `costLimit` while the screen is open, from 4 to 256 MB, and goes back on the way out. The meter is `totalCost`; players and sets are `playerCount` and `animationCount`."),
            .init("Memory warning", "Posts `UIApplication.didReceiveMemoryWarningNotification`, the notification the pool listens for. Nuke's image caches listen to the kernel's memory pressure instead, which this doesn't raise. The warning row has the pool before and at its lowest, and how long the windows stayed at two frames: about a minute, or until the app comes back from the background. Remove Idle Animations calls `removeIdleAnimations()`, which the pool does when the app enters the background."),
            .init("Lockstep", "`isSynchronizationEnabled` for every player built from then on. Switching it rebuilds every copy but the first of each animation: on, the copies join it; off, they start from the first frame. Each fixture frame shows its number. The in-step row counts the copies showing their first copy's frame."),
            .init("Transforms", "Each choice builds every player again. Tint Every Other gives half the cells a transform, so the frames row counts two sets for each animation."),
            .init("Budgets and sizes", "Player Budget is `maxBufferSize`, down to 256 KB. Frame Size Cell sets `maxPixelSize` to what the cell draws, rounded up to 32 px. Zoom draws each animation at up to eight times its natural size, cut off by the cell."),
            .init("Power", "`isPowerThrottlingEnabled` for every player. The system row reads Low Power Mode and the thermal state once a second; players with throttling on slow down in Low Power Mode or from the serious thermal state on. The fps row compares the frames each cell showed in the last second with its file's rate. A simulator has no switch for Low Power Mode, but `xcrun simctl spawn booted notifyutil -s com.apple.system.lowpowermode 1` followed by `notifyutil -p com.apple.system.lowpowermode` turns it on while the app runs, and `-s … 0` turns it off."),
            .init("Soak", "Plays for an hour: the wall is rebuilt every minute, a memory warning goes out every five minutes, and the footprint, the pool, and the players are sampled every five seconds. Drift is measured from the sample at one minute. More players alive than cells on the wall is a player that was let go and didn't go. The screen stays awake while it runs, and leaving the screen stops it. `-demoAutorun 1` starts it on open.")
        ]
    )
}

/// Starts the soak on its own only once per launch, not each time the screen
/// comes back.
@MainActor
private enum Autorun {
    static var hasRun = false
}

// MARK: - Stage

private struct AnimationLabStage: View {
    @Bindable var model: AnimationLabModel

    var body: some View {
        VStack(spacing: 12) {
            Picker("Images", selection: $model.imageSet) {
                ForEach(AnimationLabModel.ImageSet.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            wall
        }
    }

    private var wall: some View {
        ZStack {
            if !model.cells.isEmpty {
                AnimationWallLayout {
                    ForEach(model.cells) { cell in
                        AnimationWallCell(model: model, cell: cell, zoom: model.zoom)
                    }
                }
                .padding(AnimationWallLayout.spacing)
            } else if model.isLoading {
                ProgressView()
            } else if let status = model.status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { proxy in
            let inset = AnimationWallLayout.spacing * 2
            return CGSize(width: proxy.size.width - inset, height: proxy.size.height - inset)
        } action: { size in
            model.wallSize = size
        }
        .overlay(alignment: .bottom) {
            // An animation that didn't load, under the ones that did.
            if !model.cells.isEmpty, let status = model.status {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(10)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Tiles its cells in as many columns as the square root of their number, and
/// keeps each cell's view as the count changes, so that a player keeps playing
/// in the cell it started in.
struct AnimationWallLayout: Layout {
    static let spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = Self.columns(count: subviews.count)
        let cell = Self.cellSize(count: subviews.count, in: bounds.size)
        for (index, subview) in subviews.enumerated() {
            let origin = CGPoint(
                x: bounds.minX + CGFloat(index % columns) * (cell.width + Self.spacing),
                y: bounds.minY + CGFloat(index / columns) * (cell.height + Self.spacing)
            )
            subview.place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(cell))
        }
    }

    static func columns(count: Int) -> Int {
        max(1, Int(Double(count).squareRoot().rounded(.up)))
    }

    static func cellSize(count: Int, in size: CGSize) -> CGSize {
        let columns = columns(count: count)
        let rows = max(1, Int((Double(count) / Double(columns)).rounded(.up)))
        return CGSize(
            width: max(1, (size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)),
            height: max(1, (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows))
        )
    }
}

/// One animation, cut off at the cell's edges, with what its buffer holds.
private struct AnimationWallCell: View {
    let model: AnimationLabModel
    let cell: AnimationLabModel.Cell
    let zoom: CellZoom

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                // One view whatever the zoom: a view replaced by another would
                // pause the player the new one had just started as it left.
                AnimatedImage(player: cell.player, poster: cell.poster)
                    .resizable()
                    .aspectRatio(contentMode: zoom == .fit ? .fit : .fill)
                    .frame(width: zoomedSize?.width, height: zoomedSize?.height)
            }
            .clipped()
            .overlay(alignment: .bottom) {
                AnimationCellBadge(model: model, id: cell.id)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// The natural size times the zoom, or `nil` for a zoom relative to the
    /// cell.
    private var zoomedSize: CGSize? {
        guard case .scale(let scale) = zoom else { return nil }
        let source = cell.player.source.size
        let points = max(cell.player.options.scale, 1)
        return CGSize(width: source.width / points * scale, height: source.height / points * scale)
    }
}

/// The frames decoded and what they cost, as much of it as the cell has room
/// for. The fixtures show the frame on screen themselves.
private struct AnimationCellBadge: View {
    let model: AnimationLabModel
    let id: Int

    var body: some View {
        if let diagnostics = model.samples[id]?.diagnostics {
            ViewThatFits(in: .horizontal) {
                badge("\(demoFrameCount(diagnostics)) · \(demoPad(demoByteCount(diagnostics.bufferedByteCount), to: 8))")
                badge(demoFrameCount(diagnostics))
                Color.clear.frame(width: 0, height: 0)
            }
            .padding(4)
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.thinMaterial, in: Capsule())
    }
}

// MARK: - Console

/// All list, so there is only one thing to scroll. Every section is a view of
/// its own, and the figures a view of their own inside it: only what reads the
/// samples redraws ten times a second, which keeps the menus still.
private struct AnimationLabConsole: View {
    let model: AnimationLabModel

    var body: some View {
        List {
            PoolSection(model: model)
            WallSection(model: model)
            FramesSection(model: model)
            PowerSection(model: model)
            SoakSection(model: model)
            PlayersSection(model: model)
            Section {
                DemoLink(.animatedImages)
            } header: {
                Text("In the Catalog")
            } footer: {
                Text("One animation, with what its buffer map and figures mean.")
            }
        }
    }
}

private struct PoolSection: View {
    @Bindable var model: AnimationLabModel

    var body: some View {
        Section {
            PoolFigures(model: model)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            // At their natural size, centered, and without icons: with them,
            // "Memory Warning" wraps in the iPhone sheet and the iPad column.
            HStack(spacing: 12) {
                Button(model.isPaused ? "Play All" : "Pause All") {
                    model.togglePlayback()
                }
                .buttonStyle(.borderedProminent)

                Button("Memory Warning") {
                    model.sendMemoryWarning()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            Button("Remove Idle Animations") {
                model.removeIdleAnimations()
            }
            LabeledContent("Budget") {
                DemoMonoLabel(String(format: "%.0f MB", model.poolCostLimitMB))
            }
            Slider(value: $model.poolCostLimitMB, in: 4...256) {
                Text("Pool budget")
            }
        } header: {
            Text("Frame Pool")
        } footer: {
            Text("The budget is the shared pool's limit while the screen is open. A warning holds every player at two frames until the pressure passes.")
        }
    }
}

/// What the pool is holding against what it is allowed to hold, and what the
/// last warning did to it.
private struct PoolFigures: View {
    let model: AnimationLabModel

    var body: some View {
        let pool = model.pool
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(pool.fraction > 0.95 ? Color.orange : Color.accentColor)
                        .frame(width: proxy.size.width * pool.fraction)
                }
            }
            .frame(height: 10)
            DemoDiagnosticsRow("pool", "\(demoPad(demoByteCount(pool.totalCost), to: 8)) of \(demoByteCount(pool.costLimit))")
            DemoDiagnosticsRow("players", "\(pool.playerCount) sharing · \(pool.activePlayerCount) filling")
            DemoDiagnosticsRow("frames", "\(pool.animationCount) sets for \(pool.playerCount) players"
                + (pool.sharing > 1 ? String(format: " · ×%.1f", pool.sharing) : ""))
            warning
            if let removal = model.idleRemoval {
                DemoDiagnosticsRow("idle", "\(removal.setsBefore) → \(removal.setsAfter) sets · \(demoByteCount(removal.bytesFreed)) freed")
            }
        }
    }

    @ViewBuilder
    private var warning: some View {
        if let pressure = model.pressure {
            let drop = "#\(pressure.number) · \(demoByteCount(pressure.poolBefore)) → \(demoByteCount(pressure.poolLowest))"
            if let restored = pressure.restoredAfter {
                DemoDiagnosticsRow("warning", "\(drop) · back after \(demoSeconds(restored.demoTimeInterval))")
            } else if pressure.capacityBefore <= AnimationLabModel.floorFrameCount {
                DemoDiagnosticsRow("warning", "\(drop) · windows were at the floor already")
            } else {
                let held = (ContinuousClock.now - pressure.sentAt).demoTimeInterval
                DemoDiagnosticsRow("warning", "\(drop) · 2 frames for \(demoPad(demoSeconds(held), to: 5))", tint: .orange)
            }
        } else {
            DemoDiagnosticsRow("warning", "none sent")
        }
    }
}

private struct WallSection: View {
    @Bindable var model: AnimationLabModel

    var body: some View {
        Section {
            Picker("Source", selection: $model.source) {
                ForEach(DemoImageSource.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(model.imageSet == .delays)
            Picker("Cells", selection: $model.repeated) {
                Text("Each in Turn").tag(DemoAnimation?.none)
                ForEach(model.imageSet.images) { image in
                    Text("Copies of \(image.title)").tag(DemoAnimation?.some(image))
                }
            }
            Toggle("Lockstep", isOn: $model.isSynchronized)
            LockstepFigures(model: model)
            Picker("Transform", selection: $model.transform) {
                ForEach(AnimationLabModel.TransformChoice.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Wall")
        } footer: {
            Text("The delays are fixtures either way. Switching lockstep rebuilds every copy but the first of each animation, and a transform rebuilds every player.")
        }
    }
}

/// How many copies show the frame their animation's first copy shows.
private struct LockstepFigures: View {
    let model: AnimationLabModel

    var body: some View {
        var leaders: [String: Int] = [:]
        var copies = 0
        var inStep = 0
        for cell in model.cells {
            guard let frame = model.samples[cell.id]?.diagnostics.currentFrameIndex else { continue }
            let group = "\(cell.image.rawValue)|\(cell.transformID ?? "")"
            if let leader = leaders[group] {
                copies += 1
                inStep += frame == leader ? 1 : 0
            } else {
                leaders[group] = frame
            }
        }
        let text = copies == 0
            ? "no copies on the wall"
            : "\(demoPad("\(inStep)", to: "\(copies)".count)) of \(copies) copies on their first copy's frame"
        return DemoDiagnosticsRow("in step", text, tint: copies > 0 && inStep < copies ? .orange : nil)
    }
}

private struct FramesSection: View {
    @Bindable var model: AnimationLabModel

    var body: some View {
        Section {
            Picker("Player Budget", selection: $model.playerBudget) {
                ForEach(AnimationLabModel.playerBudgets, id: \.self) { budget in
                    Text(budget.map { demoByteCount($0) } ?? "None").tag(budget)
                }
            }
            Picker("Frame Size", selection: $model.frameSize) {
                ForEach(AnimationLabModel.FrameSize.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Zoom", selection: $model.zoom) {
                ForEach(CellZoom.choices, id: \.self) { Text($0.title).tag($0) }
            }
            FramesFigures(model: model)
        } header: {
            Text("Frames")
        } footer: {
            Text("A budget and a frame size build every player again; Zoom does too while the frames are decoded at the cell's size.")
        }
    }
}

/// The sizes the frames are decoded at, and how many animations are held
/// whole.
private struct FramesFigures: View {
    let model: AnimationLabModel

    var body: some View {
        let sizes = Set(model.cells.compactMap { cell in
            cell.player.image?.cgImage.map { "\($0.width)×\($0.height)" }
        }).sorted()
        let samples = model.cells.compactMap { model.samples[$0.id]?.diagnostics }
        let whole = samples.filter(\.isFullyBuffered).count
        VStack(spacing: 4) {
            DemoDiagnosticsRow("decoded", sizes.isEmpty ? "–" : sizes.joined(separator: ", ") + " px")
            DemoDiagnosticsRow("windows", "\(demoPad("\(whole)", to: 2)) whole · \(demoPad("\(samples.count - whole)", to: 2)) sliding", tint: whole < samples.count ? .orange : nil)
        }
    }
}

private struct PowerSection: View {
    @Bindable var model: AnimationLabModel

    var body: some View {
        Section {
            Toggle("Power Throttling", isOn: $model.isPowerThrottlingEnabled)
            PowerFigures(model: model)
        } header: {
            Text("Power")
        } footer: {
            Text("Throttled, a player's clock ticks at most 30 times a second. Turn on Low Power Mode and watch the frame rates follow; the info sheet has the command for a simulator.")
        }
    }
}

private struct PowerFigures: View {
    let model: AnimationLabModel

    var body: some View {
        let power = model.power
        VStack(spacing: 4) {
            DemoDiagnosticsRow("system", "Low Power Mode \(power.isLowPowerModeEnabled ? "on" : "off") · thermal \(power.thermalTitle)", tint: power.asksForLessWork ? .orange : nil)
            DemoDiagnosticsRow("clock", clock, tint: isThrottled ? .orange : nil)
            DemoDiagnosticsRow("fps", frameRates)
        }
    }

    private var isThrottled: Bool {
        model.isPowerThrottlingEnabled && model.power.asksForLessWork
    }

    private var clock: String {
        if !model.isPowerThrottlingEnabled {
            return "full rate, whatever the system asks"
        }
        return model.power.asksForLessWork ? "throttled · at most 30 ticks a second" : "full rate · the system asks for nothing"
    }

    /// Each cell's frames in the last second as a share of its file's rate:
    /// the average, and the lowest.
    private var frameRates: String {
        let shares = model.cells.compactMap { cell -> (title: String, share: Double)? in
            let nominal = cell.player.source.nominalFrameRate
            guard nominal > 0, let fps = model.samples[cell.id]?.framesPerSecond else { return nil }
            return (cell.image.title, fps / nominal)
        }
        guard let lowest = shares.min(by: { $0.share < $1.share }) else { return "measured once a second" }
        let average = shares.map(\.share).reduce(0, +) / Double(shares.count)
        return "\(percent(average)) of the files' rates · lowest \(percent(lowest.share)) \(lowest.title)"
    }

    private func percent(_ value: Double) -> String {
        demoPad("\(Int((value * 100).rounded()))%", to: 4)
    }
}

private struct SoakSection: View {
    let model: AnimationLabModel

    var body: some View {
        Section {
            if model.soak?.isRunning == true {
                Button("Stop Soak", systemImage: "stop.fill") {
                    model.stopSoak()
                }
            } else {
                Button(model.soak == nil ? "Start Soak" : "Start Again", systemImage: "play.fill") {
                    model.startSoak()
                }
            }
            if let soak = model.soak {
                SoakFigures(soak: soak)
            }
        } header: {
            Text("Soak")
        } footer: {
            Text("An hour of play, with the wall rebuilt every minute, a memory warning every five, and a sample every five seconds. The charts mark each warning with an orange tick. The screen stays awake, and leaving it stops the soak.")
        }
    }
}

private struct SoakFigures: View {
    let soak: AnimationLabModel.Soak

    private typealias Soak = AnimationLabModel.Soak

    var body: some View {
        let last = soak.samples.last
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: soak.elapsed, total: Soak.duration)
            DemoDiagnosticsRow("time", "\(clock(soak.elapsed)) of \(clock(Soak.duration)) · \(demoCount(soak.rebuildCount, "rebuild")) · \(demoCount(soak.warnings.count, "warning"))")
            chart("memory", soak.samples.map { ($0.time, $0.footprint) }, peak: soak.peakFootprint)
            chart("pool", soak.samples.map { ($0.time, $0.poolCost) }, peak: soak.peakPoolCost)
            VStack(spacing: 4) {
                DemoDiagnosticsRow("drift", drift)
                if let last {
                    DemoDiagnosticsRow(
                        "players",
                        "\(last.playerCount) alive · \(last.cellCount) cells · \(last.animationCount) sets",
                        tint: last.playerCount > last.cellCount ? .orange : nil
                    )
                }
                DemoDiagnosticsRow("decoded", "\(soak.decodedFrameCount.formatted()) frames · \(rate(soak.decodedFrameCount))/s")
                DemoDiagnosticsRow("late", "\(soak.lateFrameCount.formatted()) frames · \(rate(soak.lateFrameCount))/s", tint: soak.lateFrameCount > 0 ? .orange : nil)
                DemoDiagnosticsRow("display", "\(soak.lowestFramesPerSecond.map { "\(Int($0.rounded()))" } ?? "–") fps lowest · \(soak.display.droppedFrameCount) dropped")
            }
        }
        .padding(.vertical, 4)
    }

    /// A line laid across the whole hour, so that it grows to the right as
    /// the soak goes on, with a tick at each memory warning; under it, the
    /// latest value and the peak.
    private func chart(_ title: String, _ points: [(time: TimeInterval, value: Int)], peak: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            DemoMonoLabel(title)
                .frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                DemoSparkline(
                    samples: points.map { DemoSparkline.Sample(time: $0.time, value: Double($0.value)) },
                    ticks: soak.warnings,
                    duration: Soak.duration
                )
                .frame(height: 40)
                DemoMonoLabel("\(demoByteCount(points.last?.value ?? 0)) · peak \(demoByteCount(peak))", tint: .primary)
            }
        }
    }

    private var drift: String {
        guard let baseline = soak.baseline, let last = soak.samples.last else {
            return "from the sample at \(clock(Soak.baselineTime))"
        }
        let delta = last.footprint - baseline.footprint
        return "\(delta < 0 ? "−" : "+")\(demoByteCount(abs(delta))) since \(clock(baseline.time))"
    }

    private func rate(_ count: Int) -> String {
        String(format: "%.1f", soak.elapsed > 0 ? Double(count) / soak.elapsed : 0)
    }

    private func clock(_ time: TimeInterval) -> String {
        let seconds = Int(time)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct PlayersSection: View {
    let model: AnimationLabModel

    var body: some View {
        Section("Players") {
            ForEach(model.cells) { cell in
                if let sample = model.samples[cell.id] {
                    PlayerRow(title: cell.image.title, player: cell.player, sample: sample)
                }
            }
        }
    }
}

/// One player: what it was given and what it is holding, over its buffer map.
private struct PlayerRow: View {
    let title: String
    /// Weak, for the reason ``DemoBufferMap/player`` is.
    weak var player: AnimatedImagePlayer?
    let sample: AnimationLabModel.CellSample

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                DemoMonoLabel(figures)
                    // A row that wrapped when a figure grew would move the list.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            DemoBufferMap(player: player, diagnostics: sample.diagnostics, height: 12)
        }
        .padding(.vertical, 2)
    }

    /// Padded so that they stay put as they change.
    private var figures: String {
        let diagnostics = sample.diagnostics
        let frames = demoFrameCount(diagnostics)
        let held = demoPad(demoByteCount(diagnostics.bufferedByteCount), to: 8)
        let fps = sample.framesPerSecond.map { demoPad(String(format: "%.0f", $0), to: 3) } ?? "  –"
        let text = "\(frames) · \(held) of \(demoByteCount(diagnostics.bufferByteLimit)) · \(fps) fps"
        return diagnostics.sharingPlayerCount > 1 ? text + " · ×\(diagnostics.sharingPlayerCount)" : text
    }
}

#Preview {
    NavigationStack {
        AnimationLabDemo()
    }
}
