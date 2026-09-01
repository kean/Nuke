// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI

/// Plays one animated image with live diagnostics: what the window of decoded
/// frames is holding, what each frame costs to decode, and whether playback is
/// keeping up with the wall clock.
///
/// `LazyImage` plays animated images on its own; this screen creates the
/// ``AnimatedImagePlayer`` itself to get at ``AnimatedImagePlayer/diagnostics``.
/// The **Frame Pool** screen is the same thing for a wall of them.
///
/// The layout is a stage and a console: the picker and the animation stay put,
/// and everything that scrolls lives in an inspector – a column beside the
/// stage where there is room for one, a sheet below it where there isn't. The
/// two never overlap, so there is only ever one thing to scroll.
struct AnimatedImagesDemo: View {
    @State private var image: DemoAnimation = .gif
    @State private var settings = Settings()
    @State private var animation: DemoLoadedAnimation?
    /// Sampled on a timer rather than observed: the diagnostics change on every
    /// frame, and a view that redrew that often would be measuring itself.
    @State private var diagnostics = AnimatedImagePlayer.Diagnostics()
    @State private var status: String?
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
            .inspector(isPresented: .constant(true)) { console }
            .navigationTitle("Animated Images")
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

    @ViewBuilder
    private var canvas: some View {
        ZStack {
            if let animation {
                AnimatedImage(player: animation.player, poster: animation.poster)
                    .resizable()
                    .scaledToFit()
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

    /// The room the console leaves for the animation.
    ///
    /// Beside the stage, all of it. Below the stage, the console is presented
    /// over the screen rather than next to it, so the stage has to keep clear of
    /// it by hand. Pulling the sheet up shrinks the animation instead of
    /// covering it, which is the point of the screen: the settings that change
    /// the animation are no use without it in view.
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
    private static let collapsedConsoleHeight: CGFloat = 208
    private static let collapsedConsole = PresentationDetent.height(collapsedConsoleHeight)

    /// The transport, the diagnostics, and the settings.
    ///
    /// The transport is pinned above the list rather than being its first row,
    /// so that the sheet pushed all the way down is always the same thing – the
    /// play button and the scrubber – no matter where the list is scrolled to.
    /// The presentation modifiers only have a say when the inspector is a sheet.
    private var console: some View {
        VStack(spacing: 0) {
            transport
                .padding(.horizontal, 20)
                // The drag indicator sits in the first few points of a sheet;
                // the transport starts below it rather than under it.
                .padding(.top, isConsoleSheet ? 22 : 12)
                .padding(.bottom, 16)
            List {
                diagnosticsSection
                bufferSection
                playbackSection
            }
            .listStyle(.insetGrouped)
        }
        .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
        .presentationDetents([Self.collapsedConsole, .medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // Keeps the stage behind the sheet interactive, so the animation can be
        // scrubbed and switched while the settings change.
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .interactiveDismissDisabled()
        // The console covers the sheet the toolbar button would present, so the
        // explanation is presented from inside the inspector instead.
        .sheet(isPresented: $isShowingInfo) {
            DemoInfoSheet(info: Self.info)
        }
    }

    @ViewBuilder
    private var transport: some View {
        if let animation {
            DemoAnimationTransport(player: animation.player, diagnostics: diagnostics)
        } else {
            Text("Loading…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var diagnosticsSection: some View {
        if let animation {
            Section {
                DemoDiagnosticsPanel(player: animation.player, diagnostics: diagnostics)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            } header: {
                HStack {
                    Text("Diagnostics")
                    Spacer(minLength: 8)
                    if diagnostics.isFullyBuffered {
                        DemoBadge("Fully buffered", color: .green)
                    } else {
                        DemoBadge("Sliding window", color: .orange)
                    }
                }
            }
        }
    }

    private var bufferSection: some View {
        Section {
            LabeledContent("Budget") {
                DemoMonoLabel(settings.maxBufferSizeMB.map { String(format: "%.2f MB", $0) } ?? "pool's share (default)")
            }
            // The far end of the slider is no ceiling of the player's own,
            // which is what a player has unless it is given one. It is never
            // unbounded: the pool is the ceiling either way, and this is a
            // lower one for this player alone.
            Slider(value: Binding(
                get: { settings.maxBufferSizeMB ?? Self.maxBudgetMB },
                set: { settings.maxBufferSizeMB = $0 < Self.maxBudgetMB ? $0 : nil }
            ), in: 0.25...Self.maxBudgetMB) {
                Text("Budget")
            }
            LabeledContent("Frame size") {
                DemoMonoLabel(demoPixelSizeSubtitle(settings.maxPixelSize))
            }
            Picker("Frame size", selection: $settings.maxPixelSize) {
                ForEach(demoMaxPixelSizes, id: \.self) {
                    Text(demoPixelSize($0)).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("Frame Buffer")
        } footer: {
            Text("The most this player may use, and the longest side its frames are decoded at. The frame pool is the ceiling either way – a budget here holds this player to less than the share the pool would otherwise give it. Drop it below what the animation needs and the buffer becomes a window that slides ahead of the playhead; drop the frame size and every frame costs the square of the scale less.")
        }
    }

    private var playbackSection: some View {
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

    // MARK: Loading

    /// Everything that requires the animation to be loaded again from scratch.
    private var reloadKey: Settings.ReloadKey {
        settings.reloadKey(for: image)
    }

    private func load() async {
        // The animation on screen is replaced rather than cleared first: a
        // console that loses its diagnostics for as long as a player is being
        // built scrolls itself, and every setting here builds one.
        status = nil
        let load = await loadDemoAnimations([image], options: settings.playerOptions)
        animation = load.animations.first
        status = load.status
        sample()
    }

    private func sample() {
        diagnostics = animation?.player.diagnostics ?? AnimatedImagePlayer.Diagnostics()
    }

    /// The top of the budget slider, where it stands for no ceiling of the
    /// player's own: whatever share of the pool the animation can get.
    private static let maxBudgetMB: Double = 32

    // MARK: Model

    private struct Settings {
        /// `nil` for the default, which is a share of the frame pool.
        var maxBufferSizeMB: Double?
        var maxPixelSize: CGFloat?
        var playbackRate: Double = 1
        var repeatsForever = true

        var playerOptions: AnimatedImagePlayer.Options {
            var options = AnimatedImagePlayer.Options()
            options.maxBufferSize = maxBufferSizeMB.map { Int($0 * 1_048_576) }
            options.playbackRate = playbackRate
            options.maxPixelSize = maxPixelSize
            options.repeatCount = repeatsForever ? .infinite : .image
            return options
        }

        /// The settings a new player has to be built for. Everything else takes
        /// effect on the player that is already running.
        struct ReloadKey: Hashable {
            var image: DemoAnimation
            var maxBufferSizeMB: Double?
            var maxPixelSize: CGFloat?
            var playbackRate: Double
            var repeatsForever: Bool
        }

        func reloadKey(for image: DemoAnimation) -> ReloadKey {
            ReloadKey(
                image: image,
                maxBufferSizeMB: maxBufferSizeMB,
                maxPixelSize: maxPixelSize,
                playbackRate: playbackRate,
                repeatsForever: repeatsForever
            )
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
        """,
        points: [
            .init("Frame buffer", "The budget is in bytes of decoded frames – the canvas at four bytes a pixel, not the size of the file – and a player has none of its own unless you set one, which leaves `AnimatedImageFramePool` as its only ceiling: alone on a screen, an animation may take the whole pool, and beside others it is held whole for as long as it fits beside them. When the whole animation fits, every frame is decoded once; below that, the buffer is the frame on screen and three ahead of it, however large the budget – a window that slides re-decodes every frame each loop no matter how long it is. `maxPixelSize` scales the frames as they are decoded, and a frame costs the square of the scale: half the size is a quarter of the memory."),
            .init("Buffer map", "The bar at the top of the diagnostics is one cell per frame: filled when the frame is decoded, tinted for the frame on screen."),
            .init("Handing over from the still", "Two lines here are worth copying. The player is built with the scale of the image the pipeline decoded, and the view is given that image as its poster. Without the first, the animation changes size the moment it starts playing; without the second, the canvas is blank for as long as the first frame takes to decode."),
            .init("Diagnostics", "Everything here comes from `AnimatedImagePlayer.diagnostics`, which is available in your own app too. The demo samples it ten times a second: a view that redrew on every frame would be measuring itself. The play button doesn't need the timer – the player is an `ObservableObject` and publishes when playback starts, stops, or finishes.")
        ]
    )
}

/// The scrubber, what it is pointing at, and the buttons.
///
/// A view of its own so that it can observe the player: the button reads
/// `isPlaying` and `isFinished` straight off it, while the numbers beside the
/// scrubber move on every frame and come from the sampled diagnostics.
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
}

#Preview {
    NavigationStack {
        AnimatedImagesDemo()
    }
}
