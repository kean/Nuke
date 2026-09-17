// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// A wall of animations drawing from one budget: what
/// ``AnimatedImageFramePool`` gives each of them, and what it costs when the
/// same animation is on screen many times over.
///
/// Raise the count in the title bar and every window shrinks to a share; drag
/// the budget and they all refill. Turn on "Repeat one animation" and the wall
/// costs what a single cell did, however many cells there are.
struct AnimationMemoryDemo: View {
    @State private var image: DemoAnimation = .gif
    @State private var settings = Settings()
    @State private var animations: [DemoLoadedAnimation] = []
    /// Sampled on a timer, one per animation, in the same order.
    @State private var diagnostics: [AnimatedImagePlayer.Diagnostics] = []
    @State private var pool = DemoPoolDiagnostics()
    @State private var status: String?
    /// The limit the pool had before the screen took it over, put back on the
    /// way out: the pool is shared with every other screen.
    @State private var poolCostLimit: Int?

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
            // Before `demoConsole`, which scopes them to the stage.
            .navigationTitle("Animation Memory")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CountMenu(count: $settings.animationCount, current: settings.animationCount)
                        .equatable()
                }
            }
            .demoConsole(collapsedHeight: Self.collapsedConsoleHeight, info: Self.info) { console }
    }

    /// How many animations are on the wall, in the title bar, where it is
    /// reachable whatever the console is doing.
    ///
    /// Equatable for the reason the **Animated Images** menus are: the screen
    /// redraws ten times a second as the diagnostics are sampled, and a menu
    /// rebuilt that often drops its items while it is open.
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
                ForEach(Settings.availableCounts, id: \.self) { choice in
                    Toggle(isOn: Binding(get: { count == choice }, set: { _ in count = choice })) {
                        Text("\(choice) animations")
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

    // MARK: Stage

    private var stage: some View {
        VStack(spacing: 12) {
            Picker("Image", selection: $image) {
                ForEach(DemoAnimation.available) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            wall
        }
    }

    private var wall: some View {
        ZStack {
            if !animations.isEmpty {
                // Each cell wears what it is holding, so the effect of the pool
                // is on the wall rather than only in the diagnostics.
                DemoAnimationWall(animations: animations) { index in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        badge(at: index)
                    }
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
    }

    /// The frames of the animation that are decoded, and what they cost.
    @ViewBuilder
    private func badge(at index: Int) -> some View {
        if diagnostics.indices.contains(index) {
            let diagnostics = diagnostics[index]
            Text("\(demoFrameCount(diagnostics)) · \(demoPad(demoByteCount(diagnostics.bufferedByteCount), to: 8))")
                .font(.system(size: 9, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: Capsule())
                .padding(4)
        }
    }

    // MARK: Console

    /// Tall enough for the pool meter and a first row under it, which is what
    /// says there is more to pull up.
    private static let collapsedConsoleHeight: CGFloat = 208

    /// All list, so there is only one thing to scroll.
    private var console: some View {
        List {
            poolSection
            diagnosticsSection
        }
    }

    // MARK: Sections

    private var poolSection: some View {
        Section {
            DemoPoolMeter(pool: pool)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            // At their natural size, centered: halves of the row would truncate
            // "Free Memory" on an iPhone.
            HStack(spacing: 12) {
                Button {
                    let isPlaying = animations.contains { $0.player.isPlaying }
                    for animation in animations {
                        isPlaying ? animation.player.pause() : animation.player.play()
                    }
                } label: {
                    Label("Play All", systemImage: "playpause.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    // The same call the pool makes on a memory warning.
                    AnimatedImageFramePool.shared.reduceMemoryUsage()
                } label: {
                    Label("Free Memory", systemImage: "memorychip")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            LabeledContent("Budget") {
                DemoMonoLabel(String(format: "%.0f MB", settings.poolCostLimitMB))
            }
            Slider(value: $settings.poolCostLimitMB, in: 4...256) {
                Text("Pool budget")
            }
            Toggle("Repeat one animation", isOn: $settings.repeatsOneAnimation)
        } header: {
            Text("Frame Pool")
        } footer: {
            Text("Every animation on screen draws its frames from AnimatedImageFramePool, so a wall of them costs what the pool says rather than the sum of their budgets. Every animation is given a window of a few frames first – an even share, with what one leaves unused divided again between the rest – and what is left after that holds animations whole, smallest first.")
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
    /// Not the pool budget: changing it takes effect on the players that are
    /// already running, which is the thing worth seeing.
    private var reloadKey: Settings.ReloadKey {
        settings.reloadKey(for: image)
    }

    /// The one that is picked, repeated to fill the count, or as many of the
    /// others as there are.
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
        // The wall is replaced rather than cleared first: a console that loses
        // its diagnostics while the players are built scrolls itself to the top.
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
        /// Plays the same animation in every cell, which shows the frame sharing.
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
        "Animation Memory",
        "`AnimatedImagePlayer.Options.maxBufferSize` is per player; `AnimatedImageFramePool` is the ceiling on all of them together. Every player draws its window from the pool, so a wall of animations costs what the pool says rather than the sum of their budgets.",
        code: """
        // What every animation on screen shares
        AnimatedImageFramePool.shared.costLimit = 32 * 1_048_576

        // What it is holding right now
        AnimatedImageFramePool.shared.totalCost
        """,
        points: [
            .init("Frame pool", "Raise the animation count and watch the animations stop fitting whole – a share short of the animation buys a window of a few frames, however large – then drag the pool budget up and watch them fill again. Nothing is divided while the animations together want less than the limit."),
            .init("Windows first, then whole", "The division is not a flat split. Every animation is given its window before anything else – smallest first, so what one leaves unused is divided again between the rest – and only what is left after that holds animations whole, from the smallest up. There is no share worth giving in between: anything short of the whole animation re-decodes every frame each loop all the same."),
            .init("Shared frames", "The budget is divided between animations, not players. Turn on “Repeat one animation” and the wall costs what a single cell did, however many cells there are: one decoder, one set of frames, one window – and every cell plays in lockstep, because a player falls in behind whatever is already playing."),
            .init("Memory warnings", "The pool holds every animation at two frames when the system issues one, and the button does the same thing by hand. The windows come back a minute later, or right away if the app is backgrounded and returns – send the demo to the background and come back to watch the maps refill.")
        ]
    )
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
                DemoMonoLabel(figures)
                    // A row that wrapped when a figure grew would move the list.
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            DemoBufferMap(player: animation.player, diagnostics: diagnostics, height: 12)
        }
        .padding(.vertical, 2)
    }

    /// Padded so that they stay put as they change.
    private var figures: String {
        let frames = demoFrameCount(diagnostics)
        let held = demoPad(demoByteCount(diagnostics.bufferedByteCount), to: 8)
        let text = "\(frames) · \(held) of \(demoByteCount(diagnostics.bufferByteLimit))"
        return diagnostics.sharingPlayerCount > 1 ? text + " · ×\(diagnostics.sharingPlayerCount)" : text
    }
}

#Preview {
    NavigationStack {
        AnimationMemoryDemo()
    }
}
