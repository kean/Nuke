// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import NukeUI
import SwiftUI

/// Plays one animated image with live diagnostics: what the window of decoded
/// frames is holding, what each frame costs to decode, and whether playback is
/// keeping up with the wall clock.
///
/// `LazyImage` plays animated images on its own; this screen creates the
/// ``AnimatedImagePlayer`` itself to get at ``AnimatedImagePlayer/diagnostics``.
/// The **Animation Lab** is the same thing for a wall of them, with the knobs
/// that push it.
struct AnimatedImagesDemo: View {
    @State private var image: DemoAnimation = .gif
    @State private var settings = Settings()
    @State private var animation: DemoLoadedAnimation?
    /// What the container of each image declares, parsed once per image.
    @State private var infos: [DemoAnimation: DemoAnimationInfo] = [:]
    /// Sampled on a timer rather than observed: the diagnostics change on every
    /// frame, and a view that redrew that often would be measuring itself.
    @State private var diagnostics = AnimatedImagePlayer.Diagnostics()
    /// The shared pool, sampled on the same timer.
    @State private var pool = DemoPoolDiagnostics()
    @State private var status: String?
    @State private var isShowingImageDetails = false
    @State private var zoom: DisplayZoom = .scale(1)
    /// The zoom a pinch began from, which is what the pinch multiplies.
    @State private var zoomAtPinchStart: Double?
    @State private var displayedSize: CGSize = .zero
    /// ``displayedSize`` once it has held still for a moment: a player is built
    /// for every change of it, so a drag of the slider settles first.
    @State private var settledDisplaySize: CGSize = .zero
    @Environment(\.displayScale) private var displayScale

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        canvas
            .task(id: reloadKey) { await load() }
            .task(id: displayedSize) { await settleDisplaySize() }
            .onReceive(timer) { _ in sample() }
            // Before `demoConsole`, which scopes the title to the stage.
            .navigationTitle(image.title)
            .toolbarTitleMenu {
                ImageMenu(image: $image, current: image).equatable()
            }
            .demoConsole(collapsedHeight: Self.collapsedConsoleHeight, info: Self.info) { console }
    }

    // MARK: Stage

    /// The animation at the zoom picked from the menu in its corner, measured
    /// on the way: the size it lands at is what a "View" frame size decodes for.
    private var canvas: some View {
        GeometryReader { proxy in
            ZStack {
                if let animation {
                    stageAnimation(animation, in: proxy.size)
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
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .gesture(pinch)
        .overlay(alignment: .bottomTrailing) {
            if animation != nil {
                ZoomMenu(zoom: $zoom, current: zoom).equatable().padding(10)
            }
        }
    }

    /// The size the animation lands at is what a "View" frame size decodes
    /// for.
    private func stageAnimation(_ animation: DemoLoadedAnimation, in canvas: CGSize) -> some View {
        let size = displaySize(of: animation, in: canvas, zoom: zoom)
        return AnimatedImage(player: animation.player, poster: animation.poster)
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            .onChange(of: size, initial: true) { _, size in displayedSize = size }
    }

    /// The zoom control in the canvas corner: the named sizes, then the
    /// percentages of the natural one.
    ///
    /// Equatable because the screen redraws ten times a second as the
    /// diagnostics are sampled, and a menu rebuilt that often pulls its items
    /// out from under the tap on its way to one.
    private struct ZoomMenu: View, Equatable {
        @Binding var zoom: DisplayZoom
        /// The zoom as a plain value: the comparison runs outside the main
        /// actor, where a binding can't be read and a constant can.
        let current: DisplayZoom

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.current == rhs.current
        }

        var body: some View {
            Menu {
                ForEach(DisplayZoom.named, id: \.self) { choice in
                    item(choice)
                }
                Divider()
                ForEach(DisplayZoom.percentages, id: \.self) { choice in
                    item(choice)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(zoom.title)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
            }
        }

        private func item(_ choice: DisplayZoom) -> some View {
            Toggle(isOn: Binding(get: { zoom == choice }, set: { _ in zoom = choice })) {
                Text(choice.title)
            }
        }
    }

    /// The transport under the scrubber: step, play, step, with the rate at
    /// its trailing edge.
    private struct TransportBar: View {
        @ObservedObject var player: AnimatedImagePlayer
        @Binding var rate: Double
        let play: () -> Void
        let step: (Int) -> Void

        var body: some View {
            ZStack {
                HStack(spacing: 24) {
                    Button {
                        step(-1)
                    } label: {
                        Image(systemName: "backward.frame.fill")
                            .frame(width: 18, height: 18)
                    }
                    .accessibilityLabel("Previous frame")
                    PlayButton(player: player, play: play)
                    Button {
                        step(1)
                    } label: {
                        Image(systemName: "forward.frame.fill")
                            .frame(width: 18, height: 18)
                    }
                    .accessibilityLabel("Next frame")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                HStack {
                    Spacer()
                    RateMenu(rate: $rate, current: rate).equatable()
                }
            }
        }
    }

    /// Play, pause, or replay, in the middle of the transport.
    ///
    /// A view of its own so that it can observe the player: `isPlaying` and
    /// `isFinished` publish, so the button needs no timer.
    private struct PlayButton: View {
        @ObservedObject var player: AnimatedImagePlayer
        let play: () -> Void

        var body: some View {
            Button {
                play()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : (player.isFinished ? "arrow.clockwise" : "play.fill"))
                    .font(.title3.weight(.semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel(player.isPlaying ? "Pause" : (player.isFinished ? "Replay" : "Play"))
        }
    }

    /// The rate at the transport's edge. Equatable for the same reason as
    /// ``ZoomMenu``.
    private struct RateMenu: View, Equatable {
        @Binding var rate: Double
        let current: Double

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.current == rhs.current
        }

        private static let choices: [Double] = [0.25, 0.5, 1, 1.5, 2, 4]

        var body: some View {
            Menu {
                ForEach(Self.choices, id: \.self) { choice in
                    Toggle(isOn: Binding(get: { rate == choice }, set: { _ in rate = choice })) {
                        Text(demoRateLabel(choice))
                    }
                }
            } label: {
                Text(demoRateLabel(rate))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .accessibilityLabel("Playback rate")
        }
    }

    /// What the title's menu offers. Equatable for the same reason as
    /// ``ZoomMenu``.
    private struct ImageMenu: View, Equatable {
        @Binding var image: DemoAnimation
        let current: DemoAnimation

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.current == rhs.current
        }

        var body: some View {
            Picker("Image", selection: $image) {
                ForEach(DemoAnimation.catalog) { Text($0.title).tag($0) }
            }
        }
    }

    /// The animation at the given zoom, in points, rounded so that a change
    /// that doesn't move a pixel doesn't count as one.
    private func displaySize(of animation: DemoLoadedAnimation, in canvas: CGSize, zoom: DisplayZoom) -> CGSize {
        let size = animation.player.source.size
        guard size.width > 0, size.height > 0, canvas.width > 0, canvas.height > 0 else {
            return .zero
        }
        let scale = zoom.pointsPerPixel(for: size, imageScale: animation.player.options.scale, in: canvas)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomAtPinchStart ?? zoomScale
                zoomAtPinchStart = start
                // Up to twice the natural size: the Animation Lab goes further.
                zoom = .scale(min(2, max(0.1, start * value.magnification)))
            }
            .onEnded { _ in
                zoomAtPinchStart = nil
            }
    }

    /// The zoom in effect, read off what is drawn so that "fit" has a number.
    private var zoomScale: Double {
        guard let animation, displayedSize.width > 0 else { return 1 }
        let size = animation.player.source.size
        guard size.width > 0 else { return 1 }
        return displayedSize.width / size.width * max(animation.player.options.scale, 1)
    }

    private func settleDisplaySize() async {
        guard (try? await Task.sleep(for: .milliseconds(300))) != nil else { return }
        settledDisplaySize = displayedSize
    }

    // MARK: Console

    /// Tall enough for the buffer map, the transport under it, and a first
    /// figure or two, which is what says there is more to pull up.
    private static let collapsedConsoleHeight: CGFloat = 232

    /// All list, so there is only one thing to scroll.
    private var console: some View {
        List {
            diagnosticsSection
            bufferSection
            playbackSection
        }
    }

    // MARK: Sections

    /// The live figures, and under them what the container declares.
    @ViewBuilder
    private var diagnosticsSection: some View {
        if let animation {
            Section {
                DemoDiagnosticsPanel(
                    player: animation.player,
                    diagnostics: diagnostics,
                    drawnSize: displayedSize,
                    transport: AnyView(TransportBar(player: animation.player, rate: $settings.playbackRate, play: { togglePlayback() }, step: { step(by: $0) })),
                    pool: pool
                ) { index in
                    scrub(to: index)
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                DisclosureGroup(isExpanded: $isShowingImageDetails) {
                    DemoAnimationDetails(player: animation.player, diagnostics: diagnostics, info: infos[image])
                        .padding(.vertical, 4)
                } label: {
                    HStack {
                        Text("Image")
                        Spacer(minLength: 8)
                        DemoMonoLabel("\(infos[image]?.formatName ?? image.title) · \(animation.player.source.frameCount) frames · \(demoSeconds(animation.player.source.duration))")
                            .lineLimit(1)
                    }
                }
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
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Budget") {
                    DemoMonoLabel(settings.maxBufferSizeMB.map { String(format: "%.1f MB", $0) } ?? "pool's share")
                }
                // The far end of the slider stands for no ceiling of the
                // player's own, which still leaves the pool as the ceiling.
                Slider(value: Binding(
                    get: { settings.maxBufferSizeMB ?? Self.maxBudgetMB },
                    set: { settings.maxBufferSizeMB = $0 < Self.maxBudgetMB ? $0 : nil }
                ), in: 1...Self.maxBudgetMB) {
                    Text("Budget")
                }
                DemoMonoLabel(budgetEffect, tint: diagnostics.isFullyBuffered ? nil : .orange)
            }
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Frame size") {
                    DemoMonoLabel(frameSizeValue)
                }
                Picker("Frame size", selection: $settings.frameSize) {
                    ForEach(Settings.FrameSize.choices, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                DemoMonoLabel(frameSizeEffect, tint: settings.frameSize == .full ? nil : .accentColor)
            }
        } header: {
            Text("Frame Buffer")
        } footer: {
            Text("The pool is the ceiling either way; a budget only lowers it for this player. Below what the animation needs, the buffer becomes a window that slides ahead of the playhead. “View” decodes the frames at the size the animation is drawn at, which is what AnimatedImageView does on its own.")
        }
    }

    private var budgetEffect: String {
        guard diagnostics.frameCount > 0 else { return " " }
        guard diagnostics.isFullyBuffered else {
            return "holds \(diagnostics.bufferCapacity) of \(diagnostics.frameCount) frames · window slides"
        }
        return "holds all \(diagnostics.frameCount) frames · each decoded once"
    }

    private var frameSizeValue: String {
        switch settings.frameSize {
        case .full: "as authored"
        case .view: "\(Int(viewPixelSize)) px · the view"
        case .pixels(let size): "\(size) px"
        }
    }

    /// Computed from the setting rather than measured, so it answers before
    /// the player is built.
    private var frameSizeEffect: String {
        guard let source = animation?.player.source else { return " " }
        let canvas = source.size
        let longest = max(canvas.width, canvas.height)
        let maxPixelSize = settings.maxPixelSize(viewPixelSize: viewPixelSize) ?? longest
        let scale = min(1, maxPixelSize / max(1, longest))
        let size = CGSize(width: (canvas.width * scale).rounded(), height: (canvas.height * scale).rounded())
        let bytes = Int(size.width) * Int(size.height) * 4
        return "\(demoPixels(size)) px · \(demoByteCount(bytes)) × \(source.frameCount) = \(demoByteCount(bytes * source.frameCount))"
    }

    private var playbackSection: some View {
        Section {
            Toggle("Repeat forever", isOn: $settings.repeatsForever)
        } header: {
            Text("Playback")
        } footer: {
            Text("Off honors the loop count the file declares – a GIF without one plays once. The rate lives on the transport, under the buffer map: the delays stay as authored, and the rate is how fast the clock runs through them.")
        }
    }

    // MARK: Loading

    /// Everything that requires the animation to be loaded again from scratch.
    private var reloadKey: Settings.ReloadKey {
        settings.reloadKey(for: image, viewPixelSize: viewPixelSize)
    }

    /// The longest side of the animation as drawn, in pixels, rounded up to the
    /// step ``AnimatedImageView`` rounds to.
    private var viewPixelSize: CGFloat {
        let longest = max(settledDisplaySize.width, settledDisplaySize.height) * displayScale
        return (longest / 32).rounded(.up) * 32
    }

    private func load() async {
        // The animation is replaced rather than cleared first: a console that
        // loses its diagnostics while a player is built scrolls itself.
        let image = self.image
        status = nil
        let maxPixelSize = settings.maxPixelSize(viewPixelSize: viewPixelSize)
        let load = await loadDemoAnimations([image], options: settings.playerOptions(maxPixelSize: maxPixelSize))
        // A newer load replaced this one, and its "cancelled" isn't news.
        guard !Task.isCancelled else { return }
        animation = load.animations.first
        status = load.status
        sample()
        if infos[image] == nil, let source = load.animations.first?.player.source {
            infos[image] = await DemoAnimationInfo.parse(source)
        }
    }

    private func sample() {
        diagnostics = animation?.player.diagnostics ?? AnimatedImagePlayer.Diagnostics()
        pool = DemoPoolDiagnostics(pool: .shared)
    }

    /// Wraps around either end.
    private func step(by delta: Int) {
        guard let player = animation?.player else { return }
        let count = player.source.frameCount
        scrub(to: (player.currentFrameIndex + delta + count) % count)
    }

    /// Pauses and moves the playhead.
    private func scrub(to index: Int) {
        guard let player = animation?.player else { return }
        player.pause()
        player.seek(toFrame: index)
    }

    private func togglePlayback() {
        guard let player = animation?.player else { return }
        if player.isPlaying {
            player.pause()
        } else if player.isFinished {
            player.restart()
        } else {
            player.play()
        }
    }

    /// The top of the budget slider, where it stands for no ceiling of the
    /// player's own.
    private static let maxBudgetMB: Double = 32

    // MARK: Model

    /// How large the animation is drawn: fitted to the room there is, or a
    /// zoom of its natural size.
    private enum DisplayZoom: Hashable {
        /// As large as fits the canvas whole.
        case fit
        /// Covering the canvas, the edges trimmed.
        case fill
        /// A multiple of the natural size, which is its pixels over its scale.
        case scale(Double)

        static let named: [DisplayZoom] = [.fit, .fill, .scale(1)]
        static let percentages: [DisplayZoom] = [.scale(0.25), .scale(0.5), .scale(2)]

        var title: String {
            switch self {
            case .fit: "Fit to screen"
            case .fill: "Fill screen"
            case .scale(1): "Natural size"
            case .scale(let scale): "\(Int((scale * 100).rounded()))%"
            }
        }

        /// Points per pixel of the animation at this zoom. Fitting takes the
        /// smaller of the two scales and filling the larger, the rule
        /// `ImageProcessors.Resize` and `AnimatedImageView` use.
        func pointsPerPixel(for size: CGSize, imageScale: CGFloat, in canvas: CGSize) -> CGFloat {
            switch self {
            case .fit: min(canvas.width / size.width, canvas.height / size.height)
            case .fill: max(canvas.width / size.width, canvas.height / size.height)
            case .scale(let scale): CGFloat(scale) / max(imageScale, 1)
            }
        }
    }

    private struct Settings {
        /// `nil` for the default, which is a share of the frame pool.
        var maxBufferSizeMB: Double?
        var frameSize: FrameSize = .full
        var playbackRate: Double = 1
        var repeatsForever = true

        /// The longest side the frames are decoded at. ``AnimatedImageView``
        /// derives one from its own bounds, which is what ``view`` stands for.
        enum FrameSize: Hashable {
            /// The size the animation was authored at.
            case full
            /// The size the animation is drawn at, in pixels.
            case view
            case pixels(Int)

            static let choices: [FrameSize] = [.full, .view, .pixels(120), .pixels(240), .pixels(480)]

            var title: String {
                switch self {
                case .full: "Full"
                case .view: "View"
                case .pixels(let size): "\(size)"
                }
            }
        }

        func maxPixelSize(viewPixelSize: CGFloat) -> CGFloat? {
            switch frameSize {
            case .full: nil
            case .view: viewPixelSize > 0 ? viewPixelSize : nil
            case .pixels(let size): CGFloat(size)
            }
        }

        func playerOptions(maxPixelSize: CGFloat?) -> AnimatedImagePlayer.Options {
            var options = AnimatedImagePlayer.Options()
            options.maxBufferSize = maxBufferSizeMB.map { Int($0 * 1_048_576) }
            options.playbackRate = playbackRate
            options.maxPixelSize = maxPixelSize
            options.repeatCount = repeatsForever ? .infinite : .image
            return options
        }

        /// The settings a new player has to be built for. Everything else takes
        /// effect on the player that is already running. The frame size is in
        /// here as the pixels it resolves to, so that a "View" size rebuilds the
        /// player only when the view crosses a step.
        struct ReloadKey: Hashable {
            var image: DemoAnimation
            var maxBufferSizeMB: Double?
            var maxPixelSize: CGFloat?
            var playbackRate: Double
            var repeatsForever: Bool
        }

        func reloadKey(for image: DemoAnimation, viewPixelSize: CGFloat) -> ReloadKey {
            ReloadKey(
                image: image,
                maxBufferSizeMB: maxBufferSizeMB,
                maxPixelSize: maxPixelSize(viewPixelSize: viewPixelSize),
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
            .init("Frame buffer", "The budget is in bytes of decoded frames – the canvas at four bytes a pixel, not the size of the file – and a player has none of its own unless you set one, which leaves `AnimatedImageFramePool` as its only ceiling: alone on a screen, an animation may take the whole pool, and beside others it is held whole for as long as it fits beside them. When the whole animation fits, every frame is decoded once; below that, the buffer is the frame on screen and two ahead of it, however large the budget – a window that slides re-decodes every frame each loop no matter how long it is."),
            .init("Frame size", "`maxPixelSize` scales the frames as they are decoded, and a frame costs the square of the scale: half the size is a quarter of the memory. “View” decodes them at the size the animation is drawn at, in pixels, rounded up to 32 – the rule `AnimatedImageView` applies on its own. Pinch the animation, or pick a zoom from the menu in its corner, and watch the decoded size and the cost per frame follow it – and the “screen” line say whether the frames are being stretched or shrunk to get there."),
            .init("Buffer map", "The bar at the top of the diagnostics is one cell per frame: filled when the frame is decoded, tinted for the frame on screen. It is the scrubber too – drag across it to pause and seek. The Image row under it unfolds what was parsed from the container – the delays the file declares, and how many of them the browser rule replaced – and, when the delays differ, a second map with a bar per frame as tall as the frame is long. Mixed Delays, in the title's menu, is such an animation: its frames ask for 0, 10, 20, and 500 ms."),
            .init("Copies and memory warnings", "Every view of one animation at one size draws from one set of decoded frames, in lockstep, and the shared row counts the players on them. On a memory warning, the pool holds every animation at two frames for about a minute. The Animation Lab in the Lab puts a wall of them on screen, with frame transforms and a memory warning on a button."),
            .init("Handing over from the still","Two lines here are worth copying. The player is built with the scale of the image the pipeline decoded, and the view is given that image as its poster. Without the first, the animation changes size the moment it starts playing; without the second, the canvas is blank for as long as the first frame takes to decode."),
            .init("Diagnostics", "Everything here comes from `AnimatedImagePlayer.diagnostics`, which is available in your own app too. The demo samples it ten times a second: a view that redrew on every frame would be measuring itself. The play button doesn't need the timer – the player is an `ObservableObject` and publishes when playback starts, stops, or finishes.")
        ]
    )
}

/// "1×", "0.5×": the rate the way a player writes it on its speed control.
private func demoRateLabel(_ value: Double) -> String {
    value == value.rounded() ? "\(Int(value))×" : String(format: "%g×", value)
}

#Preview {
    NavigationStack {
        AnimatedImagesDemo()
    }
}
