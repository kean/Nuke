// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import QuartzCore
import SwiftUI

/// A screenful of animations at once: how many of them a device can play, what
/// that costs, and whether the interface still draws every frame while it does.
///
/// The **Frame Pool** screen is about how one budget is divided between
/// animations. This one is about the bill. Raise the count until the numbers
/// move: the frames the decoders produce every second, the share of a core
/// that costs, the memory the app is holding, and – the figure that decides
/// whether a screen like this is worth shipping – the rate the display is
/// actually drawing at.
///
/// Every cell wears the state of its own buffer, and tapping one opens the
/// diagnostics the **Animated Images** screen shows: in a popover beside the
/// cell where there is room for one, in the console where there isn't.
struct AnimationLoadDemo: View {
    @State private var settings = Settings()
    @State private var animations: [DemoLoadedAnimation] = []
    /// Sampled on a timer, one per animation, in the same order.
    @State private var diagnostics: [AnimatedImagePlayer.Diagnostics] = []
    @State private var pool = DemoPoolDiagnostics()
    @State private var wall = DemoWallLoad()
    @State private var readings = Readings()
    @State private var status: String?
    /// The cell whose diagnostics are open, if any.
    @State private var selection: Int?
    @State private var isShowingInfo = false
    @State private var detent: PresentationDetent = Self.collapsedConsole
    /// The space the wall has to lay the cells out in, which is what says how
    /// large the frames in them are worth decoding.
    @State private var wallSize: CGSize = .zero
    /// The limit the pool had before the screen took it over, put back on the
    /// way out: the pool is shared with every other screen in the app.
    @State private var poolCostLimit: Int?
    @State private var screen = DemoScreenFrameMeter()
    /// What decides how the console is presented: as a sheet in a compact
    /// width, as a column beside the stage otherwise.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.displayScale) private var displayScale

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        stage
            .task(id: reloadKey) { await load() }
            .onReceive(timer) { _ in sample() }
            .onChange(of: settings.poolCostLimitMB) { applyPoolCostLimit() }
            .onAppear {
                poolCostLimit = AnimatedImageFramePool.shared.costLimit
                // The screen starts at whatever this device gives animations by
                // default, which is the figure worth seeing a wall against.
                settings.poolCostLimitMB = (Double(AnimatedImageFramePool.shared.costLimit) / 1_048_576).rounded()
                screen.start()
            }
            .onDisappear {
                screen.stop()
                if let poolCostLimit {
                    AnimatedImageFramePool.shared.costLimit = poolCostLimit
                }
            }
            // The title and the info button come before `inspector`, which
            // scopes them to the stage: after it they drift into the
            // console's column.
            .navigationTitle("Animation Load")
            .demoInfoButton(isPresented: $isShowingInfo)
            .inspector(isPresented: .constant(true)) { console }
    }

    /// Whether the console is a sheet below the stage rather than a column
    /// beside it.
    private var isConsoleSheet: Bool {
        horizontalSizeClass == .compact
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                Picker("Animations", selection: $settings.count) {
                    ForEach(Settings.availableCounts, id: \.self) {
                        Text("\($0)").tag($0)
                    }
                }
                .pickerStyle(.segmented)

                grid
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            // A sheet covers the bottom edge; a column leaves it to the stage.
            .padding(.bottom, isConsoleSheet ? 0 : 16)
            .frame(height: stageHeight(in: proxy), alignment: .top)
            .animation(.snappy, value: detent)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var grid: some View {
        ZStack {
            if !animations.isEmpty {
                DemoAnimationWall(animations: animations) { index, size in
                    cell(at: index, size: size)
                }
                .padding(6)
            } else if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // The room the cells are laid out in, measured rather than computed:
        // it is what "decode at cell size" needs a number for.
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { wallSize = proxy.size }
                    .onChange(of: proxy.size) { _, size in wallSize = size }
            }
            .padding(6)
        }
    }

    /// The room the console leaves for the wall. Beside the stage, all of it;
    /// below it, whatever the sheet isn't covering – pulling the sheet up
    /// shrinks the wall instead of hiding it.
    private func stageHeight(in proxy: GeometryProxy) -> CGFloat {
        guard isConsoleSheet else {
            return proxy.size.height
        }
        let console = detent == Self.collapsedConsole
            ? Self.collapsedConsoleHeight
            // Everything above `.medium` covers the stage anyway, so the size
            // it settles on there is the smallest one worth laying out.
            : proxy.size.height / 2
        return max(200, proxy.size.height - console)
    }

    // MARK: Cells

    /// What goes over a cell: the state of its buffer in as few points as the
    /// cell can spare, and the whole of it a tap away.
    private func cell(at index: Int, size: CGSize) -> some View {
        ZStack {
            // The cell is the tap target, not the badge on it: a cell in a wall
            // of sixty-four is smaller than a fingertip as it is.
            Color.clear.contentShape(Rectangle())

            if diagnostics.indices.contains(index) {
                VStack(alignment: .leading, spacing: 3) {
                    Spacer(minLength: 0)
                    badge(at: index, size: size)
                }
                .padding(4)
            }

            if selection == index {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .onTapGesture { select(index) }
        .popover(isPresented: popover(at: index)) {
            detail(at: index)
                .padding(16)
                .frame(width: 340)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// What the cell is holding: the buffer drawn, and – where the cell is wide
    /// enough for them – the numbers beside it. A wall of sixty-four has room
    /// for the picture and nothing else, which is the point of drawing it.
    @ViewBuilder
    private func badge(at index: Int, size: CGSize) -> some View {
        let diagnostics = diagnostics[index]
        if let label = label(for: diagnostics, in: size) {
            HStack(spacing: 6) {
                buffer(at: index, width: Self.stripWidth)
                Text(label)
                    .font(.system(size: 9, design: .monospaced))
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
        } else {
            buffer(at: index, width: max(1, size.width - 8))
        }
    }

    /// The width the strip beside the numbers is drawn at.
    private static let stripWidth: CGFloat = 34

    /// The numbers that fit beside the strip: all of them, the frames alone, or
    /// none at all in a cell that has room for the strip by itself.
    private func label(for diagnostics: AnimatedImagePlayer.Diagnostics, in size: CGSize) -> String? {
        let frames = demoFrameCount(diagnostics)
        guard size.height >= 64 else { return nil }
        if size.width >= 136 {
            return "\(frames) · \(demoPad(demoByteCount(diagnostics.bufferedByteCount), to: 8))"
        }
        return size.width >= 96 ? frames : nil
    }

    /// The buffer, drawn as a cell per frame where there is a point of width
    /// for each of them, and as the fraction of the animation that is decoded
    /// where there isn't.
    @ViewBuilder
    private func buffer(at index: Int, width: CGFloat) -> some View {
        let diagnostics = diagnostics[index]
        if width / CGFloat(max(1, diagnostics.frameCount)) >= 1.5 {
            DemoBufferMap(player: animations[index].player, diagnostics: diagnostics, height: 5)
                .frame(width: width)
        } else {
            let fraction = diagnostics.frameCount > 0
                ? Double(diagnostics.bufferedFrameCount) / Double(diagnostics.frameCount) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: width * fraction)
            }
            .frame(width: width, height: 5)
        }
    }

    /// Opens the diagnostics for a cell, or closes them if they are already
    /// open. On a phone they go in the console, which has to be pulled up far
    /// enough to show them.
    private func select(_ index: Int) {
        guard selection != index else {
            return selection = nil
        }
        selection = index
    }

    /// Whether the cell's diagnostics are in a popover: only where the console
    /// is a column. iOS presents one sheet per screen, and in a compact width
    /// the console is holding it – so the detail goes in there instead, which
    /// is where a popover would have adapted to anyway.
    private func popover(at index: Int) -> Binding<Bool> {
        Binding(
            get: { !isConsoleSheet && selection == index },
            set: { isPresented in
                if !isPresented, selection == index {
                    selection = nil
                }
            }
        )
    }

    @ViewBuilder
    private func detail(at index: Int) -> some View {
        if animations.indices.contains(index), diagnostics.indices.contains(index) {
            let animation = animations[index]
            let diagnostics = diagnostics[index]
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(animation.title) · cell \(index + 1)")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    if diagnostics.isFullyBuffered {
                        DemoBadge("Fully buffered", color: .green)
                    } else {
                        DemoBadge("Sliding window", color: .orange)
                    }
                }
                DemoDiagnosticsPanel(player: animation.player, diagnostics: diagnostics)
            }
        }
    }

    // MARK: Console

    /// Tall enough for the whole transport and the first section header under
    /// it, which is what says there is more to pull up.
    private static let collapsedConsoleHeight: CGFloat = 188
    private static let collapsedConsole = PresentationDetent.height(collapsedConsoleHeight)

    /// The transport, what the wall is costing, and the settings. The
    /// presentation modifiers only have a say when the inspector is a sheet.
    private var console: some View {
        VStack(spacing: 0) {
            transport
                .padding(.horizontal, 20)
                // The drag indicator sits in the first few points of a sheet;
                // the transport starts below it rather than under it.
                .padding(.top, isConsoleSheet ? 22 : 12)
                .padding(.bottom, 16)
            List {
                if isConsoleSheet, let selection {
                    detailSection(at: selection)
                }
                loadSection
                memorySection
                settingsSection
            }
            .listStyle(.insetGrouped)
        }
        .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
        .presentationDetents([Self.collapsedConsole, .medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // Keeps the stage behind the sheet interactive, so the cells can be
        // tapped and the count changed while the settings change.
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .interactiveDismissDisabled()
        // The console covers the sheet the toolbar button would present, so the
        // explanation is presented from inside the inspector instead.
        .sheet(isPresented: $isShowingInfo) {
            DemoInfoSheet(info: Self.info)
        }
    }

    /// What applies to every animation at once, and the two figures the screen
    /// is about: what the display is managing, and what the app is holding.
    private var transport: some View {
        VStack(spacing: 12) {
            HStack {
                DemoMonoLabel("\(animations.count) animations")
                Spacer()
                DemoMonoLabel(
                    String(format: "%3.0f fps", readings.framesPerSecond),
                    tint: isDrawingSmoothly ? .green : .orange
                )
            }

            HStack {
                DemoMonoLabel("\(demoPad(demoByteCount(pool.totalCost), to: 8)) of frames")
                Spacer()
                DemoMonoLabel(readings.footprint.map { "\(demoPad(demoByteCount($0), to: 8)) in the app" } ?? "–")
            }

            HStack(spacing: 12) {
                Button {
                    let isPlaying = animations.contains { $0.player.isPlaying }
                    for animation in animations {
                        isPlaying ? animation.player.pause() : animation.player.play()
                    }
                } label: {
                    Label(isPlaying ? "Pause All" : "Play All", systemImage: "playpause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    // The same call the pool makes for itself when the system
                    // issues a memory warning.
                    AnimatedImageFramePool.shared.reduceMemoryUsage()
                } label: {
                    Label("Free Memory", systemImage: "memorychip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var isPlaying: Bool {
        animations.contains { $0.player.isPlaying }
    }

    /// Within a frame of what the display can do. The measurement is of the
    /// app's own display link, so anything the interface stalls on shows up.
    private var isDrawingSmoothly: Bool {
        readings.framesPerSecond >= screen.displayFrameRate - 1
    }

    // MARK: Sections

    private func detailSection(at index: Int) -> some View {
        Section {
            detail(at: index)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            HStack {
                Text("Cell")
                Spacer(minLength: 8)
                Button("Close") { selection = nil }
                    .font(.caption)
                    .textCase(nil)
            }
        }
    }

    private var loadSection: some View {
        Section {
            DemoDiagnosticsRow(
                "screen",
                "\(figure(readings.framesPerSecond, to: 3)) of \(figure(screen.displayFrameRate, to: 3)) fps  ·  \(demoPad("\(readings.lateFrameCount)", to: 3)) late",
                tint: isDrawingSmoothly ? nil : .orange
            )
            DemoDiagnosticsRow(
                "worst",
                "\(demoPad(demoMilliseconds(readings.worstFrameDelay), to: 7)) past a frame's deadline",
                tint: readings.worstFrameDelay > 0.1 ? .orange : nil
            )
            DemoDiagnosticsRow("playing", "\(figure(wall.frameRate, to: 4)) of \(figure(wall.nominalFrameRate, to: 4)) frames/s")
            DemoDiagnosticsRow("decoding", "\(figure(wall.decodeRate, to: 4)) frames/s  ·  \(demoPad(demoByteCount(Int(wall.decodeByteRate)), to: 8))/s")
            DemoDiagnosticsRow(
                "cores",
                String(format: "%.2f× one core, decoding", wall.decodeLoad),
                tint: wall.decodeLoad > 1 ? .orange : nil
            )
            DemoDiagnosticsRow(
                "late",
                "\(demoPad("\(wall.bufferMissCount)", to: 4)) frames not ready in time  ·  \(figure(wall.missRate, to: 4))/s",
                tint: wall.missRate > 1 ? .orange : nil
            )
            DemoDiagnosticsRow("buffers", "\(wall.fullyBufferedCount) of \(animations.count) hold the whole animation")
        } header: {
            Text("Load")
        } footer: {
            Text("The frame rate is the app's own display link: what the animations are costing the interface they are in, which is the number that decides whether a screen like this ships. Everything below it comes from the players. A window that slides never stops decoding, so \"cores\" is the share of one core the frames on screen are taking – the read-ahead is what holds it down to about one decode per frame shown.")
        }
    }

    private var memorySection: some View {
        Section {
            DemoPoolMeter(pool: pool)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            DemoDiagnosticsRow("app", appMemory)
        } header: {
            Text("Memory")
        } footer: {
            Text("The pool's figure is the decoded frames it is holding. The app's is everything: those frames, the ones the views are drawing, what the decoders keep while they work, and the rest of the app. The gap between the two is what a screenful of animations costs beyond its buffers.")
        }
    }

    private var settingsSection: some View {
        Section {
            LabeledContent("Frame pool") {
                DemoMonoLabel(String(format: "%.0f MB", settings.poolCostLimitMB))
            }
            Slider(value: $settings.poolCostLimitMB, in: 4...256) {
                Text("Frame pool")
            }
            Toggle("Decode at cell size", isOn: $settings.decodesAtCellSize)
            Toggle("Share decoded frames", isOn: $settings.sharesFrames)
        } header: {
            Text("Settings")
        } footer: {
            Text("A frame costs the square of the scale: at the size of a cell in a wall of thirty-six, a full-screen animation costs a fraction of what it does at the size it was authored. `AnimatedImageView` does this for you from its own bounds. Sharing is what an app gets for free – every copy of one animation draws from a single decoder – and turning it off is what a wall of that many *different* animations would cost.")
        }
    }

    private var appMemory: String {
        guard let footprint = readings.footprint else { return "unavailable" }
        guard let available = readings.availableMemory else {
            return "\(demoByteCount(footprint)) footprint"
        }
        return "\(demoByteCount(footprint)) footprint  ·  \(demoByteCount(available)) to spare"
    }

    /// A figure in the width it is given, so that the rows around it stay put
    /// as it changes.
    private func figure(_ value: Double, to width: Int) -> String {
        demoPad(String(format: value < 10 ? "%.1f" : "%.0f", value), to: width)
    }

    // MARK: Loading

    /// Everything that requires the wall to be built again from scratch. The
    /// pool budget is deliberately not here: changing it takes effect on the
    /// players that are already running, which is the thing worth seeing.
    private var reloadKey: Settings.ReloadKey {
        Settings.ReloadKey(
            count: settings.count,
            sharesFrames: settings.sharesFrames,
            maxPixelSize: maxPixelSize
        )
    }

    /// The animations in turn, as many times over as it takes to fill the wall:
    /// a real mix of formats, canvas sizes, and frame counts, which is what a
    /// feed of animations is.
    private var wallAnimations: [DemoAnimation] {
        let available = DemoAnimation.available
        guard !available.isEmpty else { return [] }
        return (0..<settings.count).map { available[$0 % available.count] }
    }

    /// The longest side the frames are worth decoding at: the cell they are
    /// displayed in, in pixels, rounded so that a point of layout jitter
    /// doesn't rebuild the wall.
    private var maxPixelSize: CGFloat? {
        guard settings.decodesAtCellSize, wallSize != .zero else { return nil }
        let cell = demoWallCellSize(count: settings.count, in: wallSize)
        let side = max(cell.width, cell.height) * displayScale
        return (side / 20).rounded(.up) * 20
    }

    private func load() async {
        // The wall is replaced rather than cleared first: a console that loses
        // its sections for as long as the new players are being built scrolls
        // itself back to the top.
        selection = nil
        status = nil
        wall = DemoWallLoad()
        screen.reset()
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = maxPixelSize
        let load = await loadDemoAnimations(
            wallAnimations,
            options: options,
            sharesFrames: settings.sharesFrames
        )
        // Published in one go: a wall that grew a cell at a time would rebuild
        // its views around the players already running, pausing them.
        animations = load.animations
        status = load.status
        if !settings.sharesFrames {
            // Animations that share nothing don't play in lockstep either. The
            // scattered playheads are the honest picture, and they are what
            // keeps the decoders from all wanting a frame at the same moment.
            for animation in animations {
                animation.player.seek(toFrame: .random(in: 0..<animation.player.source.frameCount))
                animation.player.play()
            }
        }
        sample()
    }

    private func sample() {
        diagnostics = animations.map { $0.player.diagnostics }
        pool = DemoPoolDiagnostics(pool: .shared)
        wall.update(animations, diagnostics, at: CACurrentMediaTime())
        readings = Readings(
            framesPerSecond: screen.framesPerSecond,
            lateFrameCount: screen.lateFrameCount,
            worstFrameDelay: screen.worstFrameDelay,
            footprint: demoMemoryFootprint(),
            availableMemory: demoAvailableMemory()
        )
    }

    private func applyPoolCostLimit() {
        AnimatedImageFramePool.shared.costLimit = Int(settings.poolCostLimitMB * 1_048_576)
        pool = DemoPoolDiagnostics(pool: .shared)
    }

    // MARK: Model

    private struct Settings {
        var count = 16
        /// Whether the frames are decoded at the size of the cell they are
        /// displayed in, which is what ``AnimatedImageView`` does on its own.
        var decodesAtCellSize = false
        /// Whether the copies of one animation draw from a single decoder,
        /// which is what they do in an app.
        var sharesFrames = true
        var poolCostLimitMB: Double = 64

        /// The counts that tile evenly.
        static let availableCounts = [4, 9, 16, 25, 36, 64]

        struct ReloadKey: Hashable {
            var count: Int
            var sharesFrames: Bool
            var maxPixelSize: CGFloat?
        }
    }

    /// What the meters read at the last sample.
    private struct Readings {
        var framesPerSecond: Double = 0
        var lateFrameCount = 0
        var worstFrameDelay: TimeInterval = 0
        var footprint: Int?
        var availableMemory: Int?
    }

    fileprivate static let info = DemoInfo(
        "Animation Load",
        "What a screenful of animations costs. The players report what they are doing; the display link says what it is costing the interface. Raise the count until one of the numbers moves – and then turn on \"Decode at cell size\" and watch most of them go back.",
        code: """
        // A frame costs the square of the scale
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = cell.width * displayScale

        // What every animation on screen is holding
        AnimatedImageFramePool.shared.totalCost
        """,
        points: [
            .init("What to watch", "The screen's frame rate first: the animations are decoded off the main thread and handed over a frame at a time, so a wall of them should cost the interface nothing until the decoders can't keep up. Then \"cores\", which is the share of one core the decoding is taking, and \"missed\", which is the frames playback was late for. A wall that is smooth, cheap, and never late is one the read-ahead is pacing perfectly."),
            .init("Decode at cell size", "The single biggest lever, and the one an app gets for free: `AnimatedImageView` decodes at its own bounds. Turn it on and every frame costs the square of the scale less – a wall of thirty-six that was sliding a two-frame window through each animation holds every one of them whole instead, and stops decoding altogether."),
            .init("Shared frames", "The pool keys the frames it holds on the animation, not the view, so the copies of one image on screen cost what a single copy did. Turn sharing off and every cell gets a decoder, a window, and a scattered playhead of its own, which is what a feed of *different* animations costs. It is the same wall on screen and several times the bill."),
            .init("Memory", "Two figures, and the gap between them is the point: the pool's is the decoded frames it is holding, the app's is what the system will judge it on. Frames on their way to the screen, the decoders' scratch space, and the images the views are still drawing all live in the gap."),
            .init("Measuring costs too", "Sixty-four players sampled ten times a second, a console redrawn as often, and a buffer map per cell: the diagnostics are work the screen wouldn't otherwise do. `AnimatedImagePlayer.diagnostics` is a snapshot you take when you want one – it costs nothing when nobody is looking.")
        ]
    )
}

/// What a wall of animations is costing, computed from the players'
/// diagnostics on every sample.
///
/// The counters in the diagnostics are cumulative; what says whether a screen
/// is keeping up is the rate they are climbing at.
private struct DemoWallLoad {
    var fullyBufferedCount = 0
    var bufferMissCount = 0
    /// The frames a second every animation on screen is asking for.
    var nominalFrameRate: Double = 0
    /// The frames a second they are actually being shown at.
    var frameRate: Double = 0
    var decodeRate: Double = 0
    var decodeByteRate: Double = 0
    /// Seconds of decoding per second of wall clock: the share of one core the
    /// frames on screen are taking. Above `1`, more than one core is busy.
    var decodeLoad: Double = 0
    var missRate: Double = 0

    private var displayed = DemoRate()
    private var decoded = DemoRate()
    private var decodedBytes = DemoRate()
    private var decodeSeconds = DemoRate()
    private var missed = DemoRate()

    @MainActor
    mutating func update(
        _ animations: [DemoLoadedAnimation],
        _ diagnostics: [AnimatedImagePlayer.Diagnostics],
        at time: TimeInterval
    ) {
        fullyBufferedCount = diagnostics.count { $0.isFullyBuffered }
        bufferMissCount = diagnostics.reduce(0) { $0 + $1.bufferMissCount }
        nominalFrameRate = animations.reduce(0) { $0 + $1.player.source.nominalFrameRate }

        var shownFrames = 0.0
        var decodedFrames = 0.0
        var decodedByteCount = 0.0
        var decodeDuration = 0.0
        for entry in diagnostics {
            shownFrames += Double(entry.displayedFrameCount)
            // A frame is decoded once and reported to every player that was
            // waiting for it, so what the work actually was is what they
            // counted, divided between them.
            let frames = Double(entry.decodedFrameCount) / Double(max(1, entry.sharingPlayerCount))
            decodedFrames += frames
            decodedByteCount += frames * Double(bytesPerFrame(entry))
            decodeDuration += frames * entry.averageDecodeDuration
        }
        displayed.update(shownFrames, at: time)
        decoded.update(decodedFrames, at: time)
        decodedBytes.update(decodedByteCount, at: time)
        decodeSeconds.update(decodeDuration, at: time)
        missed.update(Double(bufferMissCount), at: time)

        frameRate = displayed.value
        decodeRate = decoded.value
        decodeByteRate = decodedBytes.value
        decodeLoad = decodeSeconds.value
        missRate = missed.value
    }

    /// What one decoded frame of this animation costs, taken from the limit the
    /// player was given rather than from its canvas: it is the figure that
    /// knows what the decoder padded the rows to.
    private func bytesPerFrame(_ diagnostics: AnimatedImagePlayer.Diagnostics) -> Int {
        diagnostics.bufferCapacity > 0 ? diagnostics.bufferByteLimit / diagnostics.bufferCapacity : 0
    }
}

#Preview {
    NavigationStack {
        AnimationLoadDemo()
    }
}
