// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// Plays animated images with live diagnostics: what the frame buffer is
/// holding, what each frame costs to decode, and whether playback is keeping up
/// with the wall clock.
///
/// ```swift
/// LazyImage(url: url) // Plays animated images on its own
/// ```
///
/// This screen does it the long way – it creates the ``AnimatedImagePlayer``
/// itself – because that is what gives it access to
/// ``AnimatedImagePlayer/diagnostics``.
///
/// Put more than one animation on the stage and the screen becomes a picture of
/// ``AnimatedImageFramePool``: the animations share one budget, so each window
/// is a share of it rather than a budget of its own.
///
/// The layout is a stage and a console: the picker and the animations stay put,
/// and everything that scrolls lives in an inspector – a column beside the stage
/// where there is room for one, a sheet below it where there isn't. The two
/// never overlap, so there is only ever one thing to scroll.
struct AnimatedImagesDemo: View {
    @State private var image: DemoAnimation = .gif
    @State private var settings = DemoAnimationSettings()
    /// The animations on the stage: one, or a wall of them.
    @State private var animations: [DemoLoadedAnimation] = []
    /// Sampled on a timer, one per animation, in the same order.
    @State private var diagnostics: [AnimatedImagePlayer.Diagnostics] = []
    @State private var pool = DemoPoolDiagnostics()
    @State private var status: String?
    @State private var isShowingDiagnostics = true
    @State private var isShowingInfo = false
    @State private var detent: PresentationDetent = DemoAnimationConsole.collapsed
    /// The limit the pool had before the screen took it over, put back on the
    /// way out: the pool is shared with every other screen in the app.
    @State private var poolCostLimit: Int?
    /// What decides how the inspector is presented: as a sheet in a compact
    /// width, as a column beside the stage otherwise.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Sampling the diagnostics rather than observing them: they change on every
    /// frame, and a view that redrew that often would be measuring itself. The
    /// player publishes the things that don't – it starts, it stops, it
    /// finishes – so the transport doesn't wait for a tick to catch up.
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        stage
            .task(id: reloadID) { await load() }
            .onReceive(timer) { _ in sampleDiagnostics() }
            .onChange(of: settings.poolCostLimitMB) { applyPoolCostLimit() }
            .onAppear {
                poolCostLimit = AnimatedImageFramePool.shared.costLimit
                applyPoolCostLimit()
            }
            .onDisappear {
                if let poolCostLimit {
                    AnimatedImageFramePool.shared.costLimit = poolCostLimit
                }
            }
            .inspector(isPresented: .constant(true)) { console }
            .demoInfoButton(isPresented: $isShowingInfo)
    }

    /// Whether the console is a sheet below the stage rather than a column
    /// beside it.
    private var isConsoleSheet: Bool {
        horizontalSizeClass == .compact
    }

    /// The console, and how it is presented. The presentation modifiers only
    /// have a say when the inspector is a sheet.
    private var console: some View {
        DemoAnimationConsole(
            animations: animations,
            diagnostics: diagnostics,
            pool: pool,
            isSheet: isConsoleSheet,
            settings: $settings,
            isShowingDiagnostics: $isShowingDiagnostics
        )
        .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
        .presentationDetents([DemoAnimationConsole.collapsed, .medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // Keeps the stage behind the sheet interactive, so the animation can be
        // scrubbed and switched while the settings change.
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .interactiveDismissDisabled()
        // The sheet covers the one the toolbar button would present, so the
        // explanation is presented from inside the inspector instead.
        .sheet(isPresented: $isShowingInfo) {
            DemoInfoSheet(info: Self.info)
        }
    }

    fileprivate static let info = DemoInfo(
        "Animated Images",
        "NukeUI decodes the frames of an animated image off the main thread and keeps a bounded number of them in memory. Change the buffer and watch the diagnostics: when the whole animation fits, every frame is decoded once; when it does not, the decoder keeps working for as long as the animation plays.",
        code: """
        // Plays animated images on its own
        LazyImage(url: url)

        // Or, for control and diagnostics
        let player = AnimatedImagePlayer(source: source)
        AnimatedImage(player: player, poster: response.image)

        // What every animation on screen shares
        AnimatedImageFramePool.shared.costLimit = 32 * 1_048_576
        """,
        points: [
            .init("Wall clock", "Playback follows the clock rather than the decoder, so an animation always takes as long as it says it does. A frame that is not ready in time is skipped instead of stretching the timeline."),
            .init("Frame buffer", "The budget is in bytes, not frames. When the whole animation fits, every frame is decoded once; below that, the buffer becomes a window that slides ahead of the playhead."),
            .init("Frame pool", "The budget is also shared. Every player draws its window from `AnimatedImageFramePool`, so a wall of animations costs what the pool says rather than the sum of their budgets. Raise the count and watch every window shrink to a share; drag the pool budget and watch them all refill."),
            .init("Fair shares", "The division is not a flat split. An animation that fits entirely in less than its share takes only what it needs, and the rest goes to the ones that can use it – so a wall of small stickers and one long GIF gives the GIF everything the stickers left."),
            .init("Frame size", "`maxPixelSize` scales the frames as they are decoded, and a frame costs the square of the scale: half the size is a quarter of the memory. `AnimatedImageView` picks one from its own bounds; this screen builds the player by hand, so the size is yours to choose. The diagnostics show what the frames were authored at and what they are decoded at."),
            .init("Buffer map", "The bar at the top of the diagnostics is one cell per frame: filled when the frame is decoded, tinted for the frame on screen."),
            .init("Memory warnings", "The player drops its buffer to the minimum when the system issues one, and the button does the same thing by hand. The buffer isn't shrunk for good: the window it was sized for comes back a minute later, or right away if the app is backgrounded and returns – send the demo to the background and come back to watch the map refill."),
            .init("Handing over from the still", "Two lines here are worth copying. The player is built with the scale of the image the pipeline decoded, and the view is given that image as its poster. Without the first, the animation changes size the moment it starts playing; without the second, the canvas is blank for as long as the first frame takes to decode."),
            .init("Layout", "`AnimatedImage` reports the size an `Image` would, so the usual layout modifiers apply. `.fit` reports the size the frames occupy rather than the box they were offered, which is what makes the rounded background wrap the animation instead of the space around it."),
            .init("Diagnostics", "Everything here comes from `AnimatedImagePlayer.diagnostics`, which is available in your own app too. The demo samples it ten times a second: a view that redrew on every frame would be measuring itself. The play button doesn't need the timer – the player is an `ObservableObject` and publishes when playback starts, stops, or finishes.")
        ]
    )

    /// Everything that requires the animations to be loaded again from scratch.
    ///
    /// The pool budget is deliberately not here: changing it takes effect on
    /// the players that are already running, which is the thing worth seeing.
    private var reloadID: String {
        "\(image.rawValue)-\(settings.animationCount)-\(settings.maxBufferSizeMB)-\(settings.maxPixelSize.rawValue)-\(settings.playbackRate)-\(settings.repeatsForever)"
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                Picker("Image", selection: $image) {
                    ForEach(DemoAnimation.available, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)

                canvas
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

    /// The room the console leaves for the animation.
    ///
    /// Beside the stage, all of it. Below the stage, the console is presented
    /// over the screen rather than beside it, so the stage has to keep clear of
    /// it by hand. Pulling the sheet up shrinks the animation instead of
    /// covering it, which is the point of the screen: the settings that change
    /// the animation are no use without it in view.
    private func stageHeight(in proxy: GeometryProxy) -> CGFloat {
        guard isConsoleSheet else {
            return proxy.size.height
        }
        let console = detent == DemoAnimationConsole.collapsed
            ? DemoAnimationConsole.collapsedHeight
            // Everything above `.medium` covers the stage anyway, so the size
            // it settles on there is the smallest one worth laying out.
            : proxy.size.height / 2
        return max(200, proxy.size.height - console)
    }

    private var canvas: some View {
        ZStack {
            if animations.count == 1, let animation = animations.first {
                AnimatedImage(player: animation.player, poster: animation.poster)
                    .resizable(contentMode: settings.contentMode)
            } else if !animations.isEmpty {
                DemoAnimationWall(animations: animations, diagnostics: diagnostics)
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
    }

    // MARK: Loading

    /// The animations the wall plays: the one that is picked, and as many of
    /// the others as it takes to fill the count.
    ///
    /// Different images rather than the same one repeated, because that is the
    /// case the pool is for – and because Nuke decodes a frame per player, so
    /// eight copies of one GIF would be eight copies of its frames.
    private var wallAnimations: [DemoAnimation] {
        let available = DemoAnimation.available
        guard settings.animationCount > 1, let start = available.firstIndex(of: image) else {
            return [image]
        }
        return (0..<settings.animationCount).map { available[(start + $0) % available.count] }
    }

    private func load() async {
        animations = []
        diagnostics = []
        status = nil
        var loaded: [DemoLoadedAnimation] = []
        for (index, image) in wallAnimations.enumerated() {
            guard let url = image.url else {
                status = "There is no \(image.title) image on this platform."
                continue
            }
            do {
                let response = try await ImagePipeline.shared.imageTask(with: url).response
                guard let source = response.container.animation else {
                    status = "\(image.title) loaded, but it isn't an animated image."
                    continue
                }
                var options = settings.playerOptions
                // The scale of the image the pipeline decoded. `AnimatedImageView`
                // does this for the players it makes; a player built by hand has to
                // be told, or the animation changes size the moment it takes over
                // from the still.
                options.scale = response.image.scale
                let player = AnimatedImagePlayer(source: source, options: options)
                player.play()
                loaded.append(DemoLoadedAnimation(id: index, title: image.title, player: player, poster: response.image))
            } catch {
                status = "Failed to load: \(error.localizedDescription)"
            }
        }
        // Published in one go rather than as they arrive: a stage that grew a
        // cell at a time would rebuild its views around the players already
        // running, and a view being torn down pauses the player it was handed
        // and gives its window back on the way out.
        animations = loaded
        sampleDiagnostics()
    }

    private func sampleDiagnostics() {
        diagnostics = animations.map { $0.player.diagnostics }
        pool = DemoPoolDiagnostics(pool: .shared)
    }

    private func applyPoolCostLimit() {
        AnimatedImageFramePool.shared.costLimit = Int(settings.poolCostLimitMB * 1_048_576)
        pool = DemoPoolDiagnostics(pool: .shared)
    }
}

/// One animation on the stage: the player the screen drives it with, and the
/// still the decoder produced to hold its place until the first frame lands.
private struct DemoLoadedAnimation: Identifiable {
    let id: Int
    let title: String
    let player: AnimatedImagePlayer
    let poster: UIImage?
}

/// What the shared pool is doing, sampled on the same timer as the players.
private struct DemoPoolDiagnostics {
    var costLimit = 0
    var totalCost = 0
    var playerCount = 0
    var activePlayerCount = 0

    var fraction: Double {
        costLimit > 0 ? min(1, Double(totalCost) / Double(costLimit)) : 0
    }

    init() {}

    @MainActor
    init(pool: AnimatedImageFramePool) {
        costLimit = pool.costLimit
        totalCost = pool.totalCost
        playerCount = pool.playerCount
        activePlayerCount = pool.activePlayerCount
    }
}

// MARK: - Wall

/// Every animation at once, laid out to fill the stage without scrolling.
///
/// Each cell wears what it is holding, so the effect of the pool is on the
/// stage rather than only in the console: add animations and every badge drops.
private struct DemoAnimationWall: View {
    let animations: [DemoLoadedAnimation]
    let diagnostics: [AnimatedImagePlayer.Diagnostics]

    private let spacing: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let columns = max(1, Int(Double(animations.count).squareRoot().rounded(.up)))
            let rows = max(1, Int((Double(animations.count) / Double(columns)).rounded(.up)))
            let width = max(1, (proxy.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            let height = max(1, (proxy.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows))
            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { column in
                            cell(at: row * columns + column)
                                .frame(width: width, height: height)
                        }
                    }
                }
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private func cell(at index: Int) -> some View {
        if index < animations.count {
            let animation = animations[index]
            AnimatedImage(player: animation.player, poster: animation.poster)
                .resizable(contentMode: .fill)
                .overlay(alignment: .bottom) { badge(at: index) }
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func badge(at index: Int) -> some View {
        if diagnostics.indices.contains(index) {
            let diagnostics = diagnostics[index]
            Text("\(diagnostics.bufferedFrameCount)/\(diagnostics.frameCount) · \(demoByteCount(diagnostics.bufferedByteCount))")
                .font(.system(size: 9, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: Capsule())
                .padding(4)
        }
    }
}

// MARK: - Console

/// The transport, the diagnostics, and the settings.
///
/// The transport is pinned above the list rather than being its first row, so
/// that the sheet pushed all the way down is always the same thing – the play
/// button and the scrubber – no matter where the list is scrolled to.
private struct DemoAnimationConsole: View {
    let animations: [DemoLoadedAnimation]
    let diagnostics: [AnimatedImagePlayer.Diagnostics]
    let pool: DemoPoolDiagnostics
    /// Whether the console is a sheet below the stage rather than a column
    /// beside it.
    let isSheet: Bool
    @Binding var settings: DemoAnimationSettings
    @Binding var isShowingDiagnostics: Bool

    /// Tall enough for the whole transport and the first section header under
    /// it, which is what says there is more to pull up.
    static let collapsedHeight: CGFloat = 208
    static let collapsed = PresentationDetent.height(collapsedHeight)

    var body: some View {
        VStack(spacing: 0) {
            transport
                .padding(.horizontal, 20)
                // The drag indicator sits in the first few points of a sheet;
                // the transport starts below it rather than under it.
                .padding(.top, isSheet ? 22 : 12)
                .padding(.bottom, 16)
            list
        }
    }

    // MARK: Transport

    @ViewBuilder
    private var transport: some View {
        if animations.count == 1, let animation = animations.first, let diagnostics = diagnostics.first {
            DemoAnimationTransport(player: animation.player, diagnostics: diagnostics)
        } else if !animations.isEmpty {
            DemoWallTransport(players: animations.map(\.player), pool: pool)
        } else {
            Text("Loading…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: List

    private var list: some View {
        List {
            if !animations.isEmpty {
                Section {
                    if isShowingDiagnostics {
                        diagnosticsPanel
                    }
                } header: {
                    diagnosticsHeader
                }
            }

            Section {
                DemoPoolMeter(pool: pool)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                LabeledContent("Budget") {
                    DemoMonoLabel(String(format: "%.0f MB", settings.poolCostLimitMB))
                }
                Slider(value: $settings.poolCostLimitMB, in: 4...256) {
                    Text("Pool budget")
                }
                LabeledContent("Animations") {
                    DemoMonoLabel("\(settings.animationCount)")
                }
                Picker("Animations", selection: $settings.animationCount) {
                    ForEach(DemoAnimationSettings.availableCounts, id: \.self) {
                        Text("\($0)").tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Frame Pool")
            } footer: {
                Text("Every animation on screen draws its frames from AnimatedImageFramePool, so a wall of them costs what the pool says rather than the sum of their budgets. What each one gets is an even share, except that an animation that fits in less than its share takes only what it needs and leaves the rest to the others.")
            }

            Section {
                LabeledContent("Budget") {
                    DemoMonoLabel(String(format: "%.2f MB", settings.maxBufferSizeMB))
                }
                Slider(value: $settings.maxBufferSizeMB, in: 0.25...32) {
                    Text("Budget")
                }
                LabeledContent("Frame size") {
                    DemoMonoLabel(settings.maxPixelSize.subtitle)
                }
                Picker("Frame size", selection: $settings.maxPixelSize) {
                    ForEach(DemoMaxPixelSize.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Frame Buffer")
            } footer: {
                Text("The most one player may use, and the longest side its frames are decoded at. It is a ceiling on top of the pool's share: drop it below what the animation needs and the buffer becomes a sliding window; drop the frame size and every frame costs the square of the scale less.")
            }

            Section {
                Picker("Content mode", selection: $settings.contentMode) {
                    Text("Fit").tag(ContentMode.fit)
                    Text("Fill").tag(ContentMode.fill)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Layout")
            } footer: {
                Text("AnimatedImage sizes itself the way Image does. Fit takes the size the frames occupy, so a background or a clip shape wraps the animation; fill covers the space it is offered and clips what hangs over the edge.")
            }

            Section {
                LabeledContent("Rate") {
                    DemoMonoLabel(String(format: "%.2f×", settings.playbackRate))
                }
                Slider(value: $settings.playbackRate, in: 0.25...4, step: 0.25) {
                    Text("Rate")
                }
                Toggle("Repeat forever", isOn: $settings.repeatsForever)
            } header: {
                Text("Playback")
            } footer: {
                Text("The animation keeps its declared duration; the rate changes how fast the clock runs through it.")
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var diagnosticsPanel: some View {
        if animations.count == 1, let animation = animations.first, let diagnostics = diagnostics.first {
            DemoDiagnosticsPanel(player: animation.player, diagnostics: diagnostics)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } else {
            ForEach(animations) { animation in
                if diagnostics.indices.contains(animation.id) {
                    DemoWallRow(animation: animation, diagnostics: diagnostics[animation.id])
                }
            }
        }
    }

    private var diagnosticsHeader: some View {
        Button {
            withAnimation(.snappy) { isShowingDiagnostics.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text("Diagnostics")
                Spacer(minLength: 8)
                if diagnostics.allSatisfy(\.isFullyBuffered) {
                    DemoBadge("Fully buffered", color: .green)
                } else {
                    DemoBadge("Sliding window", color: .orange)
                }
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(isShowingDiagnostics ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isShowingDiagnostics ? "Hide diagnostics" : "Show diagnostics")
    }
}

/// The scrubber, what it is pointing at, and the buttons – in that order, so
/// that reading down the transport goes from the animation to the controls
/// rather than stepping over them.
///
/// A view of its own so that it can observe the player. The button reads
/// `isPlaying` and `isFinished` straight off it and is redrawn when they
/// change, which is what the player publishes; the numbers beside the scrubber
/// move on every frame and come from the sampled diagnostics instead.
private struct DemoAnimationTransport: View {
    @ObservedObject var player: AnimatedImagePlayer
    let diagnostics: AnimatedImagePlayer.Diagnostics

    var body: some View {
        VStack(spacing: 12) {
            // Scrubbing pauses first: seeking while the clock runs would hand
            // the frame straight back to the animation.
            Slider(
                value: Binding(
                    get: { Double(diagnostics.currentFrameIndex) },
                    set: {
                        player.pause()
                        player.seek(toFrame: Int($0.rounded()))
                    }
                ),
                in: 0...Double(max(1, player.source.frameCount - 1)),
                step: 1
            ) {
                Text("Frame")
            }

            HStack {
                DemoMonoLabel("frame \(diagnostics.currentFrameIndex + 1) of \(diagnostics.frameCount)")
                Spacer()
                DemoMonoLabel("loop \(diagnostics.completedLoopCount)")
            }

            HStack(spacing: 12) {
                Button {
                    if player.isPlaying {
                        player.pause()
                    } else if player.isFinished {
                        player.restart()
                    } else {
                        player.play()
                    }
                } label: {
                    Label(
                        player.isPlaying ? "Pause" : (player.isFinished ? "Replay" : "Play"),
                        systemImage: player.isPlaying ? "pause.fill" : (player.isFinished ? "arrow.clockwise" : "play.fill")
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    // The same call the player makes for itself when the system
                    // issues a memory warning.
                    player.reduceMemoryUsage()
                } label: {
                    Label("Free Memory", systemImage: "memorychip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// The transport for a wall: there is no one playhead to scrub, so what is left
/// is what applies to all of them at once.
private struct DemoWallTransport: View {
    let players: [AnimatedImagePlayer]
    let pool: DemoPoolDiagnostics

    private var isPlaying: Bool { players.contains { $0.isPlaying } }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                DemoMonoLabel("\(players.count) animations")
                Spacer()
                DemoMonoLabel("\(demoByteCount(pool.totalCost)) of \(demoByteCount(pool.costLimit))")
            }

            HStack(spacing: 12) {
                Button {
                    let isPlaying = self.isPlaying
                    for player in players {
                        isPlaying ? player.pause() : player.play()
                    }
                } label: {
                    Label(
                        isPlaying ? "Pause All" : "Play All",
                        systemImage: isPlaying ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    for player in players {
                        player.reduceMemoryUsage()
                    }
                } label: {
                    Label("Free Memory", systemImage: "memorychip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Diagnostics

/// What the pool is holding against what it is allowed to hold.
private struct DemoPoolMeter: View {
    let pool: DemoPoolDiagnostics

    var body: some View {
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
            DiagnosticsRow("pool", "\(demoByteCount(pool.totalCost)) of \(demoByteCount(pool.costLimit))")
            DiagnosticsRow("players", "\(pool.playerCount) sharing it  ·  \(pool.activePlayerCount) filling a window")
        }
    }
}

/// One line of the wall's diagnostics: what this animation was given, and what
/// it is holding.
private struct DemoWallRow: View {
    let animation: DemoLoadedAnimation
    let diagnostics: AnimatedImagePlayer.Diagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(animation.title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                DemoMonoLabel("\(diagnostics.bufferedFrameCount)/\(diagnostics.frameCount) frames  ·  \(demoByteCount(diagnostics.bufferedByteCount)) of \(demoByteCount(diagnostics.bufferByteLimit))")
            }
            BufferMap(player: animation.player, diagnostics: diagnostics, height: 12)
        }
        .padding(.vertical, 2)
    }
}

/// The numbers behind the animation.
private struct DemoDiagnosticsPanel: View {
    let player: AnimatedImagePlayer
    let diagnostics: AnimatedImagePlayer.Diagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BufferMap(player: player, diagnostics: diagnostics)
            Divider()
            grid
        }
    }

    private var grid: some View {
        VStack(spacing: 6) {
            DiagnosticsRow("frame", "\(diagnostics.currentFrameIndex + 1)/\(diagnostics.frameCount)  ·  loop \(diagnostics.completedLoopCount)")
            DiagnosticsRow("buffer", "\(diagnostics.bufferedFrameCount)/\(diagnostics.bufferCapacity) frames  ·  \(demoByteCount(diagnostics.bufferedByteCount)) of \(demoByteCount(diagnostics.bufferByteLimit))")
            DiagnosticsRow("decoded", "\(diagnostics.decodedFrameCount) frames")
            DiagnosticsRow("decode", "\(milliseconds(diagnostics.lastDecodeDuration)) last  ·  \(milliseconds(diagnostics.averageDecodeDuration)) avg  ·  \(milliseconds(diagnostics.maxDecodeDuration)) max")
            DiagnosticsRow("fps", "\(rate(diagnostics.effectiveFrameRate)) of \(rate(player.source.nominalFrameRate))")
            DiagnosticsRow("shown", "\(diagnostics.displayedFrameCount) frames in \(seconds(diagnostics.playbackTime))")
            DiagnosticsRow(
                "missed",
                "\(diagnostics.skippedFrameCount) behind  ·  \(diagnostics.bufferMissCount) not ready",
                tint: diagnostics.skippedFrameCount > 0 || diagnostics.bufferMissCount > 0 ? .orange : nil
            )
            DiagnosticsRow("size", size, tint: decodedSize == nil ? nil : .accentColor)
            DiagnosticsRow("cost", "\(demoByteCount(bytesPerDecodedFrame))/frame  ·  \(demoByteCount(player.source.data.count)) encoded")
            DiagnosticsRow("length", "\(seconds(player.source.duration))  ·  \(player.source.loopCount == 0 ? "loops forever" : "\(player.source.loopCount) loops")")
        }
    }

    /// The canvas the animation declares, and – when the frames are being
    /// scaled down – the size they are actually decoded at.
    private var size: String {
        let canvas = "\(pixels(player.source.size)) px"
        guard let decodedSize else { return canvas }
        return "\(canvas) → \(pixels(decodedSize)) px"
    }

    /// The size of the frames on screen, when it isn't the canvas size.
    ///
    /// Read off the frame the player is showing rather than computed from
    /// ``AnimatedImagePlayer/Options/maxPixelSize``, so it is what the decoder
    /// produced and not what it was asked for.
    private var decodedSize: CGSize? {
        guard let image = player.image?.cgImage else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        return size == player.source.size ? nil : size
    }

    /// What one frame costs in memory. Measured off the buffer when it holds
    /// anything, because the bitmaps are padded to a row width the compositor
    /// likes and the canvas arithmetic doesn't know about that.
    private var bytesPerDecodedFrame: Int {
        guard diagnostics.bufferedFrameCount > 0 else {
            return player.source.bytesPerFrame
        }
        return diagnostics.bufferedByteCount / diagnostics.bufferedFrameCount
    }

    private func pixels(_ size: CGSize) -> String {
        "\(Int(size.width))×\(Int(size.height))"
    }

    private func milliseconds(_ value: TimeInterval) -> String {
        String(format: "%.1fms", value * 1000)
    }

    private func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1fs", value)
    }

    private func rate(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

/// One cell per frame: filled when the frame is decoded, outlined when it isn't,
/// and tinted for the frame on screen. It is the buffer policy made visible –
/// a full row means the animation fits in memory, a moving band of filled cells
/// means it doesn't.
private struct BufferMap: View {
    let player: AnimatedImagePlayer
    let diagnostics: AnimatedImagePlayer.Diagnostics
    var height: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, diagnostics.frameCount)
            let spacing: CGFloat = count > 60 ? 0.5 : 2
            let width = max(1, (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color(for: index))
                        .frame(width: width)
                }
            }
        }
        .frame(height: height)
    }

    private func color(for index: Int) -> Color {
        if index == diagnostics.currentFrameIndex {
            return .accentColor
        }
        return player.isFrameBuffered(index) ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.07)
    }
}

private struct DiagnosticsRow: View {
    private let title: String
    private let value: String
    /// Set for the numbers worth looking at right now: orange for the frames
    /// playback couldn't keep up with, the accent color for a setting that is
    /// visibly doing something.
    private let tint: Color?

    init(_ title: String, _ value: String, tint: Color? = nil) {
        self.title = title
        self.value = value
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .foregroundStyle(tint ?? Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
    }
}

private struct DemoMonoLabel: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Model

private enum DemoAnimation: String, CaseIterable {
    case gif, apng, webp, heic, large

    /// The ones there is actually an image for on this platform.
    static var available: [DemoAnimation] {
        allCases.filter { $0.url != nil }
    }

    var title: String {
        switch self {
        case .gif: "GIF"
        case .apng: "APNG"
        case .webp: "WebP"
        case .heic: "HEIC"
        case .large: "Large"
        }
    }

    var url: URL? {
        switch self {
        case .gif: DemoImages.gif
        case .apng: DemoImages.apng
        case .webp: DemoImages.animatedWebP
        case .heic: DemoImages.animatedHEIC
        case .large: DemoImages.largeGIF
        }
    }
}

private struct DemoAnimationSettings {
    var maxBufferSizeMB: Double = 10
    /// What every animation on screen shares. Smaller than the pool's own
    /// default, so that a wall of animations reaches it.
    var poolCostLimitMB: Double = 64
    var animationCount: Int = 1
    var playbackRate: Double = 1
    var maxPixelSize: DemoMaxPixelSize = .full
    var repeatsForever = true
    /// The only setting here that isn't a player option: it belongs to the
    /// view, so changing it doesn't reload the animation.
    var contentMode: ContentMode = .fit

    /// The wall sizes: a single animation, and the counts that tile evenly.
    static let availableCounts = [1, 4, 9, 16]

    var playerOptions: AnimatedImagePlayer.Options {
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = Int(maxBufferSizeMB * 1_048_576)
        options.playbackRate = playbackRate
        options.maxPixelSize = maxPixelSize.value
        options.repeatCount = repeatsForever ? .infinite : .image
        return options
    }
}

/// The longest side the frames are decoded at.
///
/// The biggest memory lever there is: a frame costs the square of the scale, so
/// decoding at half the size is a quarter of the memory and four times as many
/// frames in the same budget. ``AnimatedImageView`` derives one from its own
/// size; a player built by hand, like this screen's, takes what it is given.
private enum DemoMaxPixelSize: Int, CaseIterable, Identifiable {
    case full = 0
    case small = 120
    case medium = 240
    case large = 480

    var id: Int { rawValue }

    var title: String { self == .full ? "Full" : "\(rawValue)" }

    var subtitle: String { self == .full ? "as authored" : "\(rawValue) px" }

    var value: CGFloat? { self == .full ? nil : CGFloat(rawValue) }
}

#Preview {
    NavigationStack {
        AnimatedImagesDemo()
    }
}
