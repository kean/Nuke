// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// A wall of animations drawing from one budget: what
/// ``AnimatedImageFramePool`` gives each of them, and what it costs when the
/// same animation is on screen many times over.
///
/// Add animations and every window shrinks to a share; drag the budget and
/// they all refill. Turn on "Repeat one animation" and the wall costs what a
/// single cell did, however many cells there are.
///
/// The layout is the same one the **Animated Images** screen uses: a stage that
/// stays put, and a console in an inspector – a column beside the wall where
/// there is room for one, a sheet below it where there isn't.
struct AnimatedImageFramePoolDemo: View {
    @State private var image: DemoAnimation = .gif
    @State private var settings = Settings()
    @State private var animations: [DemoLoadedAnimation] = []
    /// Sampled on a timer, one per animation, in the same order.
    @State private var diagnostics: [AnimatedImagePlayer.Diagnostics] = []
    @State private var pool = DemoPoolDiagnostics()
    @State private var status: String?
    /// The limit the pool had before the screen took it over, put back on the
    /// way out: the pool is shared with every other screen in the app.
    @State private var poolCostLimit: Int?
    @State private var isShowingInfo = false
    @State private var detent: PresentationDetent = Self.collapsedConsole
    /// What decides how the console is presented: as a sheet in a compact
    /// width, as a column beside the stage otherwise.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        stage
            .task(id: reloadKey) { await load() }
            .onReceive(timer) { _ in sample() }
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
            .navigationTitle("Frame Pool")
            .demoInfoButton(isPresented: $isShowingInfo)
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
                Picker("Image", selection: $image) {
                    ForEach(DemoAnimation.available) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                wall
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
    private var wall: some View {
        ZStack {
            if !animations.isEmpty {
                DemoAnimationWall(animations: animations, diagnostics: diagnostics)
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
    }

    /// The room the console leaves for the wall. Beside the stage, all of it;
    /// below it, whatever the sheet isn't covering – pulling the sheet up
    /// shrinks the wall instead of hiding it, which is the point of the screen.
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

    // MARK: Console

    /// Tall enough for the whole transport and the first section header under
    /// it, which is what says there is more to pull up.
    private static let collapsedConsoleHeight: CGFloat = 164
    private static let collapsedConsole = PresentationDetent.height(collapsedConsoleHeight)

    /// The transport, the pool settings, and the per-animation diagnostics. The
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
                poolSection
                diagnosticsSection
            }
            .listStyle(.insetGrouped)
        }
        .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
        .presentationDetents([Self.collapsedConsole, .medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // Keeps the stage behind the sheet interactive, so the animations can be
        // played and switched while the settings change.
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .interactiveDismissDisabled()
        // The console covers the sheet the toolbar button would present, so the
        // explanation is presented from inside the inspector instead.
        .sheet(isPresented: $isShowingInfo) {
            DemoInfoSheet(info: Self.info)
        }
    }

    /// What applies to every animation at once. There is no one playhead to
    /// scrub, so this is all a wall's transport can be.
    private var transport: some View {
        VStack(spacing: 12) {
            HStack {
                DemoMonoLabel("\(animations.count) animations")
                Spacer()
                DemoMonoLabel("\(demoByteCount(pool.totalCost)) of \(demoByteCount(pool.costLimit))")
            }

            HStack(spacing: 12) {
                Button {
                    let isPlaying = animations.contains { $0.player.isPlaying }
                    for animation in animations {
                        isPlaying ? animation.player.pause() : animation.player.play()
                    }
                } label: {
                    Label("Play All", systemImage: "playpause.fill")
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

    // MARK: Sections

    private var poolSection: some View {
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
                ForEach(Settings.availableCounts, id: \.self) {
                    Text("\($0)").tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Toggle("Repeat one animation", isOn: $settings.repeatsOneAnimation)
        } header: {
            Text("Frame Pool")
        } footer: {
            Text("Every animation on screen draws its frames from AnimatedImageFramePool, so a wall of them costs what the pool says rather than the sum of their budgets. What each one gets is an even share, except that an animation that fits in less than its share takes only what it needs and leaves the rest to the others.")
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            ForEach(animations) { animation in
                if diagnostics.indices.contains(animation.id) {
                    DemoWallRow(animation: animation, diagnostics: diagnostics[animation.id])
                }
            }
        }
    }

    // MARK: Loading

    /// Everything that requires the animations to be loaded again from scratch.
    ///
    /// The pool budget is deliberately not here: changing it takes effect on
    /// the players that are already running, which is the thing worth seeing.
    private var reloadKey: Settings.ReloadKey {
        settings.reloadKey(for: image)
    }

    /// The one that is picked repeated as many times as it takes to fill the
    /// count – which is what shows the frame sharing – or as many of the others
    /// as there are.
    private var wallAnimations: [DemoAnimation] {
        guard !settings.repeatsOneAnimation else {
            return Array(repeating: image, count: settings.animationCount)
        }
        let available = DemoAnimation.available
        guard let start = available.firstIndex(of: image) else {
            return [image]
        }
        return (0..<settings.animationCount).map { available[(start + $0) % available.count] }
    }

    private func load() async {
        animations = []
        diagnostics = []
        status = nil
        let load = await loadDemoAnimations(wallAnimations)
        // Published in one go: a wall that grew a cell at a time would rebuild
        // its views around the players already running, pausing them.
        animations = load.animations
        status = load.status
        sample()
    }

    private func sample() {
        diagnostics = animations.map { $0.player.diagnostics }
        pool = DemoPoolDiagnostics(pool: .shared)
    }

    private func applyPoolCostLimit() {
        AnimatedImageFramePool.shared.costLimit = Int(settings.poolCostLimitMB * 1_048_576)
        pool = DemoPoolDiagnostics(pool: .shared)
    }

    // MARK: Model

    private struct Settings {
        /// Smaller than the pool's own default, so that a wall of animations
        /// reaches it.
        var poolCostLimitMB: Double = 64
        var animationCount = 4
        /// Whether the wall plays the same animation in every cell, which is
        /// what shows the frame sharing.
        var repeatsOneAnimation = false

        /// The counts that tile evenly.
        static let availableCounts = [4, 9, 16]

        /// The settings the wall has to be built again for. The pool budget
        /// isn't one: it takes effect on the players already running.
        struct ReloadKey: Hashable {
            var image: DemoAnimation
            var animationCount: Int
            var repeatsOneAnimation: Bool
        }

        func reloadKey(for image: DemoAnimation) -> ReloadKey {
            ReloadKey(
                image: image,
                animationCount: animationCount,
                repeatsOneAnimation: repeatsOneAnimation
            )
        }
    }

    fileprivate static let info = DemoInfo(
        "Frame Pool",
        "`AnimatedImagePlayer.Options.maxBufferSize` is per player; `AnimatedImageFramePool` is the ceiling on all of them together. Every player draws its window from the pool, so a wall of animations costs what the pool says rather than the sum of their budgets.",
        code: """
        // What every animation on screen shares
        AnimatedImageFramePool.shared.costLimit = 32 * 1_048_576

        // What it is holding right now
        AnimatedImageFramePool.shared.totalCost
        """,
        points: [
            .init("Frame pool", "Raise the animation count and watch the animations stop fitting whole – a share short of the animation buys a window of a few frames, however large – then drag the pool budget up and watch them fill again. Nothing is divided while the animations together want less than the limit."),
            .init("Fair shares", "The division is not a flat split. An animation that fits entirely in less than its share takes only what it needs, and the rest goes to the ones that can use it – so a wall of small stickers and one long GIF gives the GIF everything the stickers left."),
            .init("Shared frames", "The budget is divided between animations, not players. Turn on “Repeat one animation” and the wall costs what a single cell did, however many cells there are: one decoder, one set of frames, one window – and every cell plays in lockstep, because a player falls in behind whatever is already playing."),
            .init("Memory warnings", "The pool holds every animation at two frames when the system issues one, and the button does the same thing by hand. The windows come back a minute later, or right away if the app is backgrounded and returns – send the demo to the background and come back to watch the maps refill.")
        ]
    )
}

/// What the shared pool is doing, sampled on the same timer as the players.
private struct DemoPoolDiagnostics {
    var costLimit = 0
    var totalCost = 0
    var playerCount = 0
    var activePlayerCount = 0
    var animationCount = 0

    var fraction: Double {
        costLimit > 0 ? min(1, Double(totalCost) / Double(costLimit)) : 0
    }

    /// How many players there are for every set of decoded frames.
    var sharing: Double {
        animationCount > 0 ? Double(playerCount) / Double(animationCount) : 0
    }

    init() {}

    @MainActor
    init(pool: AnimatedImageFramePool) {
        costLimit = pool.costLimit
        totalCost = pool.totalCost
        playerCount = pool.playerCount
        activePlayerCount = pool.activePlayerCount
        animationCount = pool.animationCount
    }
}

/// Every animation at once, laid out to fill the stage without scrolling.
///
/// Each cell wears what it is holding, so the effect of the pool is on the wall
/// rather than only in the diagnostics: add animations and every badge drops.
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
                            cell(at: row * columns + column, width: width, height: height)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(at index: Int, width: CGFloat, height: CGFloat) -> some View {
        if index < animations.count {
            let animation = animations[index]
            AnimatedImage(player: animation.player, poster: animation.poster)
                .resizable()
                .scaledToFill()
                // Before the badge and the corners: filling means the frames
                // are larger than the cell, and what hangs over the edge is
                // the cell's to trim.
                .frame(width: width, height: height)
                .clipped()
                .overlay(alignment: .bottom) { badge(at: index) }
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Color.clear.frame(width: width, height: height)
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
            DemoDiagnosticsRow("pool", "\(demoByteCount(pool.totalCost)) of \(demoByteCount(pool.costLimit))")
            DemoDiagnosticsRow("players", "\(pool.playerCount) sharing it  ·  \(pool.activePlayerCount) filling a window")
            // The players outnumber the animations as soon as one of them is on
            // screen twice.
            DemoDiagnosticsRow("frames", "\(pool.animationCount) sets for \(pool.playerCount) players"
                + (pool.sharing > 1 ? String(format: "  ·  %.1f× shared", pool.sharing) : ""))
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
                DemoMonoLabel("\(diagnostics.bufferedFrameCount)/\(diagnostics.frameCount) frames  ·  \(demoByteCount(diagnostics.bufferedByteCount)) of \(demoByteCount(diagnostics.bufferByteLimit))"
                    + (diagnostics.sharingPlayerCount > 1 ? "  ·  shared ×\(diagnostics.sharingPlayerCount)" : ""))
            }
            DemoBufferMap(player: animation.player, diagnostics: diagnostics, height: 12)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        AnimatedImageFramePoolDemo()
    }
}
