// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI
import UIKit

/// A wall of animations playing at once from the shared
/// `AnimatedImageFramePool`, with what the pool holds and the knobs that push
/// it: its budget, a memory warning, and lockstep.
///
/// It reports numbers, and leaves explaining them to **Animated Images** in the
/// catalog, which does it for one animation.
struct AnimationLabDemo: View {
    @State private var model = AnimationLabModel()

    var body: some View {
        wall
            .task { await model.run() }
            // Before `demoConsole`, which scopes them to the stage.
            .navigationTitle("Animation Lab")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Animations", selection: $model.count) {
                            ForEach(AnimationLabModel.counts, id: \.self) { Text(demoCount($0, "animation")).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(model.count)")
                                .monospacedDigit()
                            Image(systemName: "square.grid.2x2")
                                .imageScale(.small)
                        }
                    }
                    .accessibilityLabel("Number of animations")
                }
            }
            .demoConsole(collapsedHeight: 208, info: Self.info) {
                AnimationLabConsole(model: model)
            }
    }

    /// Doesn't read the samples, so that the menu above isn't rebuilt ten
    /// times a second: one rebuilt while it is open drops its items.
    private var wall: some View {
        ZStack {
            if !model.cells.isEmpty {
                AnimationWallLayout {
                    ForEach(model.cells) { cell in
                        AnimationWallCell(model: model, cell: cell)
                    }
                }
                .padding(AnimationWallLayout.spacing)
            } else if model.status == nil {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let status = model.status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private static let info = DemoInfo(
        "Animation Lab",
        "Up to 36 animations playing at once, every one drawing its frames from the shared `AnimatedImageFramePool`. **Animated Images** in the catalog says what the figures mean for one of them.",
        points: [
            .init("Wall", "The count is in the title bar, and the cells keep their players as it changes. They take a GIF, an APNG, a WebP, a HEIC, and a long GIF in turn, all fixtures, and every one repeats forever. The badge on a cell is the frames and the bytes its buffer holds."),
            .init("Frame pool", "The budget is `costLimit` while the screen is open, from 4 to 256 MB, and goes back on the way out. The meter is `totalCost`, with `playerCount` players on `animationCount` sets of frames."),
            .init("Memory warning", "Posts `UIApplication.didReceiveMemoryWarningNotification`, which the pool answers by holding every player at two frames for a minute. The row has the pool before the warning and at its lowest since."),
            .init("Lockstep", "`isSynchronizationEnabled` for every player built from then on. Switching it rebuilds every copy but the first of each animation: in lockstep the copies join it, out of it they start from the first frame.")
        ]
    )
}

// MARK: - Wall

/// Tiles its cells in as many columns as the square root of their number, and
/// keeps each cell's view as the count changes, so that a player keeps playing
/// in the cell it started in.
private struct AnimationWallLayout: Layout {
    static let spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = max(1, Int(Double(subviews.count).squareRoot().rounded(.up)))
        let rows = max(1, (subviews.count + columns - 1) / columns)
        let cell = CGSize(
            width: (bounds.width - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns),
            height: (bounds.height - Self.spacing * CGFloat(rows - 1)) / CGFloat(rows)
        )
        for (index, subview) in subviews.enumerated() {
            let origin = CGPoint(
                x: bounds.minX + CGFloat(index % columns) * (cell.width + Self.spacing),
                y: bounds.minY + CGFloat(index / columns) * (cell.height + Self.spacing)
            )
            subview.place(at: origin, proposal: ProposedViewSize(cell))
        }
    }
}

/// One animation covering its cell, with what its buffer holds.
private struct AnimationWallCell: View {
    let model: AnimationLabModel
    let cell: AnimationLabModel.Cell

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                AnimatedImage(player: cell.player, poster: cell.animation.poster)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .overlay(alignment: .bottom) {
                AnimationCellBadge(model: model, id: cell.id)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// The frames and the bytes buffered, as much of it as the cell has room for.
/// A view of its own, so that the samples redraw only the badge.
private struct AnimationCellBadge: View {
    let model: AnimationLabModel
    let id: Int

    var body: some View {
        if let diagnostics = model.diagnostics[id] {
            ViewThatFits(in: .horizontal) {
                badge("\(demoFrameCount(diagnostics)) · \(demoPad(demoByteCount(diagnostics.bufferedByteCount), to: 8))")
                badge(demoFrameCount(diagnostics))
                Color.clear.frame(width: 0, height: 0)
            }
            .padding(.bottom, 4)
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.thinMaterial, in: Capsule())
    }
}

// MARK: - Console

private struct AnimationLabConsole: View {
    @Bindable var model: AnimationLabModel

    var body: some View {
        List {
            Section {
                PoolFigures(model: model)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                // Without icons: with them, "Memory Warning" wraps in the
                // iPhone sheet.
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
                LabeledContent("Budget") {
                    DemoMonoLabel(String(format: "%.0f MB", model.poolCostLimitMB))
                }
                Slider(value: $model.poolCostLimitMB, in: 4...256) {
                    Text("Pool budget")
                }
                Toggle("Lockstep", isOn: $model.isSynchronized)
            } header: {
                Text("Frame Pool")
            } footer: {
                Text("The budget is the shared pool's limit while the screen is open. Switching lockstep rebuilds every copy but the first of each animation.")
            }
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

/// What the pool holds against its budget, and what the last memory warning
/// did to it. A view of its own, so that the samples redraw only the figures.
private struct PoolFigures: View {
    let model: AnimationLabModel

    var body: some View {
        let pool = model.pool
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: pool.fraction)
                .tint(pool.fraction > 0.95 ? .orange : .accentColor)
            DemoDiagnosticsRow("pool", "\(demoPad(demoByteCount(pool.totalCost), to: 8)) of \(demoByteCount(pool.costLimit))")
            DemoDiagnosticsRow("players", "\(pool.playerCount) on \(demoCount(pool.animationCount, "set")) of frames")
            if let warning = model.warning {
                DemoDiagnosticsRow("warning", "\(demoByteCount(warning.before)) → \(demoByteCount(warning.lowest)) at the lowest")
            } else {
                DemoDiagnosticsRow("warning", "none sent")
            }
        }
    }
}

// MARK: - Model

/// The cells on the wall, and what is sampled about them and the pool.
@MainActor @Observable
final class AnimationLabModel {
    static let counts = [1, 4, 9, 16, 25, 36]

    var count = 4 { didSet { resize() } }

    /// ``AnimatedImagePlayer/Options/isSynchronizationEnabled`` for every
    /// player built from now on.
    var isSynchronized = true { didSet { rejoin() } }

    /// Smaller than the pool's own default, so that a wall reaches it.
    var poolCostLimitMB: Double = 64 { didSet { applyPoolCostLimit() } }

    private(set) var cells: [Cell] = []
    private(set) var isPaused = false
    /// Why an animation isn't on the wall, or `nil` when every one is.
    private(set) var status: String?
    /// Sampled ten times a second: a view that followed every frame would be
    /// measuring itself.
    private(set) var diagnostics: [Cell.ID: AnimatedImagePlayer.Diagnostics] = [:]
    private(set) var pool = DemoPoolDiagnostics()
    /// The pool before the last memory warning, and at its lowest since.
    private(set) var warning: (before: Int, lowest: Int)?

    struct Cell: Identifiable {
        /// New for every player, so that a cell rebuilt in place is a new view.
        let id: Int
        let animation: LoadedAnimation
        let player: AnimatedImagePlayer
    }

    struct LoadedAnimation {
        let image: DemoAnimation
        let source: AnimatedImageSource
        let poster: UIImage
    }

    @ObservationIgnored private var animations: [LoadedAnimation] = []
    @ObservationIgnored private var nextCellID = 0

    /// Loads the wall and samples it until the screen goes away. The pool is
    /// shared with every other screen, so it gets its own limit back then.
    func run() async {
        let savedCostLimit = AnimatedImageFramePool.shared.costLimit
        defer { AnimatedImageFramePool.shared.costLimit = savedCostLimit }
        applyPoolCostLimit()
        await load()
        while !Task.isCancelled {
            sample()
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func load() async {
        guard animations.isEmpty else { return }
        var messages: [String] = []
        for image in DemoAnimation.formats {
            do throws(DemoAnimationError) {
                let (source, poster) = try await image.load(fromFixture: true)
                animations.append(LoadedAnimation(image: image, source: source, poster: poster))
            } catch {
                messages.append(error.message)
            }
        }
        status = messages.isEmpty ? nil : messages.joined(separator: "\n")
        resize()
    }

    private func sample() {
        diagnostics = Dictionary(uniqueKeysWithValues: cells.map { ($0.id, $0.player.diagnostics) })
        pool = DemoPoolDiagnostics(pool: .shared)
        if let warning {
            self.warning?.lowest = min(warning.lowest, pool.totalCost)
        }
    }

    private func applyPoolCostLimit() {
        AnimatedImageFramePool.shared.costLimit = Int(poolCostLimitMB * 1_048_576)
    }

    func togglePlayback() {
        isPaused.toggle()
        for cell in cells {
            isPaused ? cell.player.pause() : cell.player.play()
        }
    }

    /// Sends what the system sends when it runs short of memory, which is what
    /// the pool listens for.
    func sendMemoryWarning() {
        let cost = AnimatedImageFramePool.shared.totalCost
        warning = (cost, cost)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
        sample()
    }

    /// Drops cells from the end or adds them there, in one go: a wall that
    /// grew a cell at a time would be laid out again for every one.
    private func resize() {
        guard !animations.isEmpty else { return }
        let kept = Array(cells.prefix(count))
        cells = kept + (kept.count..<count).map { makeCell(animations[$0 % animations.count]) }
    }

    /// Rebuilds every cell but the first of each animation, which keeps
    /// playing: in lockstep the new players join it, out of it they start from
    /// the first frame.
    private func rejoin() {
        var firsts = Set<DemoAnimation>()
        cells = cells.map { firsts.insert($0.animation.image).inserted ? $0 : makeCell($0.animation) }
    }

    private func makeCell(_ animation: LoadedAnimation) -> Cell {
        var options = AnimatedImagePlayer.Options()
        options.repeatCount = .infinite
        // Without it the animation changes size as it takes over from the still.
        options.scale = animation.poster.scale
        options.isSynchronizationEnabled = isSynchronized
        nextCellID += 1
        return Cell(id: nextCellID, animation: animation, player: AnimatedImagePlayer(source: animation.source, options: options))
    }
}

#Preview {
    NavigationStack {
        AnimationLabDemo()
    }
}
