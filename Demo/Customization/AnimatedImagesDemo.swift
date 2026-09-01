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
/// The layout is a stage and a console: the animation stays put with play and
/// zoom in its corners, the image is picked from the title's menu, and
/// everything else lives in an inspector – a column beside the stage where
/// there is room for one, a sheet below it where there isn't. The console is
/// all list: nothing is pinned above it, so there is only one thing to
/// scroll and it all scrolls.
struct AnimatedImagesDemo: View {
    @State private var image: DemoAnimation = .gif
    @State private var settings = Settings()
    @State private var animation: DemoLoadedAnimation?
    /// What the container of each image declares, parsed once per image: none
    /// of it changes with the settings, and a long GIF takes a scan to read.
    @State private var infos: [DemoAnimation: DemoAnimationInfo] = [:]
    /// Sampled on a timer rather than observed: the diagnostics change on every
    /// frame, and a view that redrew that often would be measuring itself.
    @State private var diagnostics = AnimatedImagePlayer.Diagnostics()
    @State private var status: String?
    @State private var isShowingInfo = false
    @State private var isShowingImageDetails = false
    @State private var detent: PresentationDetent = Self.collapsedConsole
    /// How large the animation is drawn on the stage.
    @State private var zoom: DisplayZoom = .fit
    /// The zoom a pinch began from, as a scale of the natural size, which is
    /// what the pinch multiplies.
    @State private var zoomAtPinchStart: Double?
    /// The size the animation is drawn at, in points, as the stage lays it out.
    @State private var displayedSize: CGSize = .zero
    /// ``displayedSize`` once it has held still for a moment. It is what a
    /// "View" frame size decodes for, and a player is built for every change
    /// of it – so a drag of the slider or a sheet on its way up settles first.
    @State private var settledDisplaySize: CGSize = .zero
    /// What decides how the console is presented: as a sheet in a compact
    /// width, as a column beside the stage otherwise.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.displayScale) private var displayScale

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        stage
            .task(id: reloadKey) { await load() }
            .task(id: displayedSize) { await settleDisplaySize() }
            .onReceive(timer) { _ in sample() }
            .inspector(isPresented: .constant(true)) { console }
            // The title is the image, the way a title menu wants it: it names
            // what the menu under it switches.
            .navigationTitle(image.title)
            .toolbarTitleMenu {
                ImageMenu(image: $image, current: image).equatable()
            }
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
            canvas
                .padding(.horizontal, 16)
                .padding(.top, 12)
                // A sheet covers the bottom edge; a column leaves it to the
                // stage.
                .padding(.bottom, isConsoleSheet ? 0 : 16)
                .frame(height: stageHeight(in: proxy), alignment: .top)
                .animation(.snappy, value: detent)
        }
        .background(Color(.systemGroupedBackground))
    }

    /// The animation at the zoom picked from the menu in its corner, measured
    /// on the way: the size it lands at is what a "View" frame size decodes
    /// for. A zoom past the canvas is trimmed by it, the way a preview canvas
    /// trims what it can't fit.
    @ViewBuilder
    private var canvas: some View {
        GeometryReader { proxy in
            ZStack {
                if let animation {
                    let size = displaySize(of: animation, in: proxy.size)
                    AnimatedImage(player: animation.player, poster: animation.poster)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                        .onChange(of: size, initial: true) { _, size in displayedSize = size }
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
        .overlay(alignment: .bottomLeading) {
            if let animation {
                PlayButton(player: animation.player).padding(10)
            }
        }
    }

    /// The zoom control a preview canvas has in its corner: the named sizes,
    /// then the percentages of the natural one. Whatever a pinch left the zoom
    /// at is named by its percentage and checks nothing.
    ///
    /// A view of its own, compared by the zoom alone. The screen redraws ten
    /// times a second as the diagnostics are sampled, and a menu rebuilt that
    /// often pulls its items out from under the tap on its way to one – so
    /// while the zoom stands still, the menu the system is showing is left
    /// alone.
    private struct ZoomMenu: View, Equatable {
        @Binding var zoom: DisplayZoom
        /// The zoom again as a plain value: the comparison runs outside the
        /// main actor, where a binding can't be read and a constant can.
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

        /// A toggle rather than a button, for the checkmark on the one in
        /// effect.
        private func item(_ choice: DisplayZoom) -> some View {
            Toggle(isOn: Binding(get: { zoom == choice }, set: { _ in zoom = choice })) {
                Text(choice.title)
            }
        }
    }

    /// Play, pause, or replay, in the canvas corner opposite the zoom.
    ///
    /// A view of its own so that it can observe the player: `isPlaying` and
    /// `isFinished` publish, so the button needs no timer.
    private struct PlayButton: View {
        @ObservedObject var player: AnimatedImagePlayer

        var body: some View {
            Button {
                if player.isPlaying {
                    player.pause()
                } else if player.isFinished {
                    player.restart()
                } else {
                    player.play()
                }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : (player.isFinished ? "arrow.clockwise" : "play.fill"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 14, height: 15)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : (player.isFinished ? "Replay" : "Play"))
        }
    }

    /// What the title's menu offers, held apart from the sampling for the same
    /// reason as ``ZoomMenu``: equal means the open menu keeps its items.
    private struct ImageMenu: View, Equatable {
        @Binding var image: DemoAnimation
        /// The image again as a plain value, for the same reason as
        /// ``ZoomMenu/current``.
        let current: DemoAnimation

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.current == rhs.current
        }

        var body: some View {
            Picker("Image", selection: $image) {
                ForEach(DemoAnimation.available) { Text($0.title).tag($0) }
            }
        }
    }

    /// The animation at the zoom, in points. Rounded to whole points so that a
    /// change that doesn't move a pixel doesn't count as one.
    private func displaySize(of animation: DemoLoadedAnimation, in canvas: CGSize) -> CGSize {
        let size = animation.player.source.size
        guard size.width > 0, size.height > 0, canvas.width > 0, canvas.height > 0 else {
            return .zero
        }
        let scale = zoom.pointsPerPixel(for: size, imageScale: animation.player.options.scale, in: canvas)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// Pinching the animation zooms it, from wherever the menu left it.
    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomAtPinchStart ?? zoomScale
                zoomAtPinchStart = start
                zoom = .scale(min(8, max(0.1, start * value.magnification)))
            }
            .onEnded { _ in
                zoomAtPinchStart = nil
            }
    }

    /// The zoom in effect as a scale of the natural size, whichever way it was
    /// chosen: read off what is drawn, so that "fit" has a number too.
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

    /// Tall enough for the buffer map – the scrubber – and a first figure or
    /// two under it, which is what says there is more to pull up.
    private static let collapsedConsoleHeight: CGFloat = 176
    private static let collapsedConsole = PresentationDetent.height(collapsedConsoleHeight)

    /// The diagnostics and the settings, and nothing pinned above them:
    /// playback lives on the canvas, so the console is all list and all of it
    /// scrolls. The presentation modifiers only have a say when the inspector
    /// is a sheet.
    private var console: some View {
        List {
            diagnosticsSection
            bufferSection
            playbackSection
        }
        .listStyle(.insetGrouped)
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

    // MARK: Sections

    /// The live figures, and under them – folded away – what the container
    /// declares about the image.
    @ViewBuilder
    private var diagnosticsSection: some View {
        if let animation {
            Section {
                // Scrubbing pauses first: seeking while the clock runs would
                // hand the frame straight back to the animation.
                DemoDiagnosticsPanel(player: animation.player, diagnostics: diagnostics, drawnSize: displayedSize) { index in
                    animation.player.pause()
                    animation.player.seek(toFrame: index)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                // One frame at a time: the map above is the scrubber, and
                // these are its fine adjustment – which is how to read the
                // delay map, one bar per tap.
                HStack(spacing: 12) {
                    Button {
                        step(by: -1)
                    } label: {
                        Label("Previous frame", systemImage: "backward.frame.fill")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        step(by: 1)
                    } label: {
                        Label("Next frame", systemImage: "forward.frame.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .controlSize(.small)
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

    /// Two settings, each with what it comes to for this animation right under
    /// it: the budget in frames held, the frame size in pixels and bytes.
    private var bufferSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Budget") {
                    DemoMonoLabel(settings.maxBufferSizeMB.map { String(format: "%.2f MB", $0) } ?? "pool's share")
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
            Button {
                // The same call the pool makes for itself when the system
                // issues a memory warning.
                AnimatedImageFramePool.shared.reduceMemoryUsage()
            } label: {
                Label("Free Memory", systemImage: "memorychip")
            }
        } header: {
            Text("Frame Buffer")
        } footer: {
            Text("The pool is the ceiling either way; a budget only lowers it for this player. Below what the animation needs, the buffer becomes a window that slides ahead of the playhead. “View” decodes the frames at the size the animation is drawn at, which is what AnimatedImageView does on its own.")
        }
    }

    /// What the budget comes to, off the player running under it: the whole
    /// animation, or a window.
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

    /// The size the frames come out at, and what they cost: computed from the
    /// setting rather than measured, so it answers before the player is built.
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
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Rate") {
                    DemoMonoLabel(String(format: "%.2f×", settings.playbackRate))
                }
                Slider(value: $settings.playbackRate, in: 0.25...4, step: 0.25) {
                    Text("Rate")
                }
            }
            Toggle("Repeat forever", isOn: $settings.repeatsForever)
        } header: {
            Text("Playback")
        } footer: {
            Text("The delays stay as authored; the rate is how fast the clock runs through them.")
        }
    }

    // MARK: Loading

    /// Everything that requires the animation to be loaded again from scratch.
    private var reloadKey: Settings.ReloadKey {
        settings.reloadKey(for: image, viewPixelSize: viewPixelSize)
    }

    /// The longest side of the animation as drawn, in pixels, rounded up to
    /// the step ``AnimatedImageView`` rounds to – so that a view a point wider
    /// doesn't decode the animation at a size of its own.
    private var viewPixelSize: CGFloat {
        let longest = max(settledDisplaySize.width, settledDisplaySize.height) * displayScale
        return (longest / 32).rounded(.up) * 32
    }

    private func load() async {
        // The animation on screen is replaced rather than cleared first: a
        // console that loses its diagnostics for as long as a player is being
        // built scrolls itself, and every setting here builds one.
        let image = self.image
        status = nil
        let maxPixelSize = settings.maxPixelSize(viewPixelSize: viewPixelSize)
        let load = await loadDemoAnimations([image], options: settings.playerOptions(maxPixelSize: maxPixelSize))
        animation = load.animations.first
        status = load.status
        sample()
        if infos[image] == nil, let source = load.animations.first?.player.source {
            infos[image] = await DemoAnimationInfo.parse(source)
        }
    }

    private func sample() {
        diagnostics = animation?.player.diagnostics ?? AnimatedImagePlayer.Diagnostics()
    }

    /// Pauses and moves the playhead by the given number of frames, wrapping
    /// around either end.
    private func step(by delta: Int) {
        guard let player = animation?.player else { return }
        player.pause()
        let count = player.source.frameCount
        player.seek(toFrame: (player.currentFrameIndex + delta + count) % count)
    }

    /// The top of the budget slider, where it stands for no ceiling of the
    /// player's own: whatever share of the pool the animation can get.
    private static let maxBudgetMB: Double = 32

    // MARK: Model

    /// How large the animation is drawn on the stage, the way a preview canvas
    /// offers it: fitted to the room there is, or a zoom of its natural size.
    private enum DisplayZoom: Hashable {
        /// As large as fits the canvas whole.
        case fit
        /// Covering the canvas, the edges trimmed.
        case fill
        /// A multiple of the natural size – the one an `Image` draws it at,
        /// which is its pixels over its scale. `1` is the natural size itself.
        case scale(Double)

        static let named: [DisplayZoom] = [.fit, .fill, .scale(1)]
        static let percentages: [DisplayZoom] = [.scale(0.25), .scale(0.5), .scale(2), .scale(4)]

        var title: String {
            switch self {
            case .fit: "Fit to screen"
            case .fill: "Fill screen"
            case .scale(1): "Natural size"
            case .scale(let scale): "\(Int((scale * 100).rounded()))%"
            }
        }

        /// Points per pixel of the animation at this zoom.
        ///
        /// Fitting takes the smaller of the two scales and filling the larger:
        /// the rule `ImageProcessors.Resize` and `AnimatedImageView` use.
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
        /// derives one from its own bounds, which is what ``view`` stands for;
        /// a player built by hand takes what it is given.
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

        /// - parameter viewPixelSize: The longest side of the animation as
        /// drawn, in pixels, for ``FrameSize/view``.
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
        /// effect on the player that is already running.
        ///
        /// The frame size is in here as the pixels it resolves to, so that a
        /// "View" size only rebuilds the player when the view crosses a step.
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
            .init("Buffer map", "The bar at the top of the diagnostics is one cell per frame: filled when the frame is decoded, tinted for the frame on screen. It is the scrubber too – drag across it to pause and seek. The Image row under it unfolds what was parsed from the container – the delays the file declares, and how many of them the browser rule replaced – and, when the delays differ, a second map with a bar per frame as tall as the frame is long."),
            .init("Handing over from the still", "Two lines here are worth copying. The player is built with the scale of the image the pipeline decoded, and the view is given that image as its poster. Without the first, the animation changes size the moment it starts playing; without the second, the canvas is blank for as long as the first frame takes to decode."),
            .init("Diagnostics", "Everything here comes from `AnimatedImagePlayer.diagnostics`, which is available in your own app too. The demo samples it ten times a second: a view that redrew on every frame would be measuring itself. The play button doesn't need the timer – the player is an `ObservableObject` and publishes when playback starts, stops, or finishes.")
        ]
    )
}

#Preview {
    NavigationStack {
        AnimatedImagesDemo()
    }
}
