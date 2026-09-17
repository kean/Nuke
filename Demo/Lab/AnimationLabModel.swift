// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI
import UIKit

/// The wall of the Animation Lab and everything measured about it: the
/// players, the pool, the power state, the last memory warning, and the soak.
///
/// The settings are properties with observers: a change schedules one pass
/// that brings the wall up to date, and a burst of changes is one pass. The
/// wall is rebuilt only for the settings a player is created with. A new count
/// adds or drops cells at the end and leaves the rest playing, and a new
/// lockstep setting rebuilds every copy but the first of each animation, so
/// that the copies either join it or start over.
@MainActor @Observable
final class AnimationLabModel {
    // MARK: Settings

    var imageSet = ImageSet.formats {
        didSet {
            if let repeated, !imageSet.images.contains(repeated) {
                self.repeated = nil
            }
            setNeedsUpdate()
        }
    }

    /// Where the formats come from. The delays are fixtures either way.
    var source = DemoImageSource.fixtures { didSet { setNeedsUpdate() } }

    /// The animation every cell plays, or `nil` for the set in turn.
    var repeated: DemoAnimation? { didSet { setNeedsUpdate() } }

    var count = 4 { didSet { setNeedsUpdate() } }

    /// ``AnimatedImagePlayer/Options/isSynchronizationEnabled`` for every
    /// player built from now on.
    var isSynchronized = true { didSet { setNeedsUpdate() } }

    var transform = TransformChoice.none { didSet { setNeedsUpdate() } }

    /// ``AnimatedImagePlayer/Options/maxBufferSize`` for every player, in
    /// bytes.
    var playerBudget: Int? { didSet { setNeedsUpdate() } }

    var frameSize = FrameSize.full { didSet { setNeedsUpdate() } }

    var zoom = CellZoom.fill { didSet { setNeedsUpdate() } }

    var isPowerThrottlingEnabled = true { didSet { setNeedsUpdate() } }

    /// Smaller than the pool's own default, so that a wall reaches it.
    var poolCostLimitMB: Double = 64 {
        didSet { applyPoolCostLimit() }
    }

    /// The size of the wall, in points, for frames decoded at the size of a
    /// cell. Settled before it is used: a player is built for every change.
    var wallSize: CGSize = .zero {
        didSet {
            guard wallSize != oldValue else { return }
            settleWallSize()
        }
    }

    var displayScale: CGFloat = 2 {
        didSet {
            guard displayScale != oldValue else { return }
            setNeedsUpdate()
        }
    }

    // MARK: Wall

    /// The cells in the order the wall lays them out.
    private(set) var cells: [Cell] = []
    /// Why an animation isn't on the wall, or `nil` when every one is.
    private(set) var status: String?
    /// Whether the first wall is still being loaded.
    var isLoading: Bool { !isBuilt }

    struct Cell: Identifiable {
        /// New for every player, so that a cell rebuilt in place is a new view.
        let id: Int
        let image: DemoAnimation
        let player: AnimatedImagePlayer
        let poster: UIImage
        /// The identifier of the transform its frames are decoded with; copies
        /// share frames only while it matches.
        let transformID: String?
    }

    // MARK: Figures

    /// Sampled ten times a second: a view that followed every frame would be
    /// measuring itself.
    private(set) var samples: [Cell.ID: CellSample] = [:]
    private(set) var pool = DemoPoolDiagnostics()
    private(set) var power = PowerState.current
    private(set) var pressure: Pressure?
    private(set) var idleRemoval: IdleRemoval?
    private(set) var soak: Soak?

    struct CellSample {
        var diagnostics: AnimatedImagePlayer.Diagnostics
        /// Frames shown per second over the last second, or `nil` before a
        /// whole second has passed.
        var framesPerSecond: Double?
    }

    /// What the system says about power, read once a second.
    struct PowerState: Equatable {
        var isLowPowerModeEnabled = false
        var thermalState = ProcessInfo.ThermalState.nominal

        static var current: PowerState {
            let info = ProcessInfo.processInfo
            return PowerState(isLowPowerModeEnabled: info.isLowPowerModeEnabled, thermalState: info.thermalState)
        }

        /// Whether a player with throttling on runs a slower clock: in Low
        /// Power Mode, or from the serious thermal state on.
        var asksForLessWork: Bool {
            isLowPowerModeEnabled || thermalState == .serious || thermalState == .critical
        }

        var thermalTitle: String {
            switch thermalState {
            case .nominal: "nominal"
            case .fair: "fair"
            case .serious: "serious"
            case .critical: "critical"
            @unknown default: "unknown"
            }
        }
    }

    /// The last memory warning the screen sent, and what the pool did.
    struct Pressure {
        let sentAt: ContinuousClock.Instant
        /// Warnings sent since the screen opened.
        let number: Int
        let poolBefore: Int
        var poolLowest: Int
        /// The largest window a player had before the warning.
        let capacityBefore: Int
        /// Whether every window has been seen at the floor since.
        var reachedFloor = false
        /// How long the windows stayed at the floor, once one grew again.
        var restoredAfter: Duration?
    }

    struct IdleRemoval {
        let setsBefore: Int
        let setsAfter: Int
        let bytesFreed: Int
    }

    // MARK: Watching

    @ObservationIgnored private let monitor = DemoDisplayMonitor()
    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    @ObservationIgnored private var tickCount = 0
    /// Where each cell's frame count stood at the last fps reading.
    @ObservationIgnored private var fpsMarks: [Cell.ID: (frames: Int, time: ContinuousClock.Instant)] = [:]
    /// The pool's limit before the screen took it over, put back on the way
    /// out: the pool is shared with every other screen.
    @ObservationIgnored private var savedPoolCostLimit: Int?

    /// Samples ten times a second, and counts frames, while the screen is on
    /// display.
    func startWatching() {
        monitor.start()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopWatching() {
        samplingTask?.cancel()
        samplingTask = nil
        monitor.stop()
    }

    func appear() {
        if savedPoolCostLimit == nil {
            savedPoolCostLimit = AnimatedImageFramePool.shared.costLimit
        }
        applyPoolCostLimit()
        setNeedsUpdate()
    }

    func disappear() {
        stopSoak()
        if let savedPoolCostLimit {
            AnimatedImageFramePool.shared.costLimit = savedPoolCostLimit
            self.savedPoolCostLimit = nil
        }
    }

    private func tick() {
        tickCount += 1
        let now = ContinuousClock.now
        let isSecond = tickCount % 10 == 0
        sample(now: now, readsFrameRate: isSecond)
        if isSecond {
            let power = PowerState.current
            if power != self.power {
                self.power = power
            }
            if soak?.isRunning == true {
                advanceSoak(now: now)
            }
        }
    }

    /// Reads every player and the pool; once a second, the frame rates too.
    private func sample(now: ContinuousClock.Instant = .now, readsFrameRate: Bool = false) {
        var samples: [Cell.ID: CellSample] = [:]
        for cell in cells {
            let diagnostics = cell.player.diagnostics
            var fps = self.samples[cell.id]?.framesPerSecond
            if readsFrameRate {
                if let mark = fpsMarks[cell.id] {
                    let seconds = (now - mark.time).demoTimeInterval
                    fps = seconds > 0 ? Double(diagnostics.displayedFrameCount - mark.frames) / seconds : nil
                }
                fpsMarks[cell.id] = (diagnostics.displayedFrameCount, now)
            }
            samples[cell.id] = CellSample(diagnostics: diagnostics, framesPerSecond: fps)
        }
        if readsFrameRate {
            fpsMarks = fpsMarks.filter { samples[$0.key] != nil }
        }
        self.samples = samples
        pool = DemoPoolDiagnostics(pool: .shared)
        trackPressure(now: now)
    }

    // MARK: Pool

    private func applyPoolCostLimit() {
        AnimatedImageFramePool.shared.costLimit = Int(poolCostLimitMB * 1_048_576)
        pool = DemoPoolDiagnostics(pool: .shared)
    }

    func togglePlayback() {
        let isPlaying = cells.contains { $0.player.isPlaying }
        for cell in cells {
            isPlaying ? cell.player.pause() : cell.player.play()
        }
    }

    /// Sends what the system sends when it runs short of memory. The pool is
    /// the one listening; Nuke's image caches watch the kernel's memory
    /// pressure instead, which this doesn't raise.
    func sendMemoryWarning() {
        let pool = AnimatedImageFramePool.shared
        pressure = Pressure(
            sentAt: .now,
            number: (pressure?.number ?? 0) + 1,
            poolBefore: pool.totalCost,
            poolLowest: pool.totalCost,
            capacityBefore: cells.map { $0.player.diagnostics.bufferCapacity }.max() ?? 0
        )
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
        sample()
    }

    /// Follows the pool down after a warning, and times the windows coming
    /// back: every cell held at the two frames of the floor, then one holding
    /// more.
    private func trackPressure(now: ContinuousClock.Instant) {
        guard var pressure, pressure.restoredAfter == nil, pressure.capacityBefore > Self.floorFrameCount else { return }
        pressure.poolLowest = min(pressure.poolLowest, pool.totalCost)
        let capacities = samples.values.map(\.diagnostics.bufferCapacity)
        if !pressure.reachedFloor {
            pressure.reachedFloor = !capacities.isEmpty && capacities.allSatisfy { $0 <= Self.floorFrameCount }
        } else if capacities.contains(where: { $0 > Self.floorFrameCount }) {
            pressure.restoredAfter = now - pressure.sentAt
        }
        self.pressure = pressure
    }

    /// What a player holds under memory pressure.
    static let floorFrameCount = 2

    /// What the pool does when the app goes to the background.
    func removeIdleAnimations() {
        let pool = AnimatedImageFramePool.shared
        let before = (sets: pool.animationCount, bytes: pool.totalCost)
        pool.removeIdleAnimations()
        idleRemoval = IdleRemoval(setsBefore: before.sets, setsAfter: pool.animationCount, bytesFreed: max(0, before.bytes - pool.totalCost))
        self.pool = DemoPoolDiagnostics(pool: pool)
    }

    // MARK: Building the Wall

    /// Everything a player is created with, other than lockstep, which
    /// doesn't rebuild the wall.
    private struct BuildKey: Equatable {
        var images: [DemoAnimation]
        var source: DemoImageSource
        var transform: TransformChoice
        var playerBudget: Int?
        var isPowerThrottlingEnabled: Bool
        /// The size frames are decoded for, when it is the cell's.
        var drawing: Drawing?
    }

    private struct Drawing: Equatable {
        var cell: CGSize
        var zoom: CellZoom
        var displayScale: CGFloat
    }

    private struct Built {
        var key: BuildKey
        var count: Int
        var isSynchronized: Bool
    }

    @ObservationIgnored private var built: Built? {
        didSet { isBuilt = built != nil }
    }
    /// ``built`` for the views, which only need to know whether it exists.
    private var isBuilt = false
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    /// Set by the soak: the next pass builds every player again.
    @ObservationIgnored private var needsRebuild = false
    @ObservationIgnored private var nextCellID = 0
    @ObservationIgnored private var responses: [ResponseKey: Response] = [:]
    @ObservationIgnored private var failures: [DemoAnimation: String] = [:]
    @ObservationIgnored private var settledWallSize: CGSize = .zero
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    private struct ResponseKey: Hashable {
        var image: DemoAnimation
        var source: DemoImageSource
    }

    private typealias Response = (animation: AnimatedImageSource, poster: UIImage)

    /// The animations of the set that exist on this platform.
    private var availableImages: [DemoAnimation] {
        imageSet.images.filter { $0.url(from: source) != nil }
    }

    /// The animation of every cell, in order.
    private func cellImages(count: Int) -> [DemoAnimation] {
        if let repeated {
            return Array(repeating: repeated, count: count)
        }
        let images = availableImages
        guard !images.isEmpty else { return [] }
        return (0..<count).map { images[$0 % images.count] }
    }

    private var buildKey: BuildKey {
        BuildKey(
            images: repeated.map { [$0] } ?? availableImages,
            source: source,
            transform: transform,
            playerBudget: playerBudget,
            isPowerThrottlingEnabled: isPowerThrottlingEnabled,
            drawing: frameSize == .cell && settledWallSize != .zero
                ? Drawing(cell: AnimationWallLayout.cellSize(count: count, in: settledWallSize), zoom: zoom, displayScale: displayScale)
                : nil
        )
    }

    private func settleWallSize() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(300))) != nil, let self else { return }
            settledWallSize = wallSize
            if frameSize == .cell {
                setNeedsUpdate()
            }
        }
    }

    /// Schedules one pass for however many settings change in this update.
    private func setNeedsUpdate() {
        guard updateTask == nil else { return }
        updateTask = Task { [weak self] in
            await Task.yield()
            await self?.update()
            self?.updateTask = nil
        }
    }

    /// Brings the wall up to date, and again for whatever changed while it
    /// was loading.
    private func update() async {
        while !Task.isCancelled {
            let key = buildKey
            if needsRebuild || key != built?.key {
                needsRebuild = false
                await rebuild(key: key)
            } else if let built, built.count != count {
                resize(to: count, isSynchronized: isSynchronized)
            } else if let built, built.isSynchronized != isSynchronized {
                rejoin(isSynchronized: isSynchronized)
            } else {
                return
            }
        }
    }

    /// A new player for every cell, published in one go: a wall that grew a
    /// cell at a time would lay its cells out again for every one.
    private func rebuild(key: BuildKey) async {
        await loadResponses(for: key)
        guard key == buildKey else { return } // Changed while loading
        let images = cellImages(count: count)
        cells = images.indices.compactMap { makeCell(at: $0, image: images[$0], isSynchronized: isSynchronized) }
        built = Built(key: key, count: count, isSynchronized: isSynchronized)
        sample()
    }

    /// Adds cells at the end, which join the copies already playing when
    /// lockstep is on, or drops cells from the end.
    private func resize(to count: Int, isSynchronized: Bool) {
        let images = cellImages(count: count)
        var cells = Array(self.cells.prefix(count))
        for index in cells.count..<images.count {
            if let cell = makeCell(at: index, image: images[index], isSynchronized: isSynchronized) {
                cells.append(cell)
            }
        }
        self.cells = cells
        built?.count = count
        built?.isSynchronized = isSynchronized
        sample()
    }

    /// Rebuilds every cell but the first copy of each animation, which keeps
    /// playing: with lockstep on, the new players join it; off, they start
    /// from the first frame.
    private func rejoin(isSynchronized: Bool) {
        var leaders = Set<String>()
        cells = cells.enumerated().map { index, cell in
            let group = "\(cell.image.rawValue)|\(cell.transformID ?? "")"
            guard !leaders.insert(group).inserted else { return cell }
            return makeCell(at: index, image: cell.image, isSynchronized: isSynchronized) ?? cell
        }
        built?.isSynchronized = isSynchronized
        sample()
    }

    private func loadResponses(for key: BuildKey) async {
        var messages: [String] = []
        for image in key.images {
            let responseKey = ResponseKey(image: image, source: key.source)
            guard responses[responseKey] == nil else { continue }
            do throws(DemoAnimationError) {
                responses[responseKey] = try await image.load(from: key.source)
                failures[image] = nil
            } catch {
                failures[image] = error.message
                messages.append(error.message)
            }
        }
        if key.images.isEmpty {
            messages.append("There is no image in this set on this platform.")
        }
        status = messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private func makeCell(at index: Int, image: DemoAnimation, isSynchronized: Bool) -> Cell? {
        guard let response = responses[ResponseKey(image: image, source: source)] else {
            return nil
        }
        let transform = transform.frameTransform(at: index)
        var options = AnimatedImagePlayer.Options()
        // A wall that plays for an hour keeps playing: a file that asks to
        // play once would stop decoding after its first loop.
        options.repeatCount = .infinite
        options.scale = response.poster.scale
        options.maxBufferSize = playerBudget
        options.maxPixelSize = maxPixelSize(for: response.animation, scale: response.poster.scale)
        options.frameTransform = transform
        options.isSynchronizationEnabled = isSynchronized
        options.isPowerThrottlingEnabled = isPowerThrottlingEnabled
        let player = AnimatedImagePlayer(source: response.animation, options: options)
        player.play()
        nextCellID += 1
        return Cell(id: nextCellID, image: image, player: player, poster: response.poster, transformID: transform?.identifier)
    }

    /// The longest side of the animation as drawn in a cell, in pixels,
    /// rounded up to the 32 px step `AnimatedImageView` uses, or `nil` for
    /// full-size frames.
    private func maxPixelSize(for animation: AnimatedImageSource, scale: CGFloat) -> CGFloat? {
        guard frameSize == .cell, let drawing = buildKey.drawing else { return nil }
        let scale = max(scale, 1)
        let natural = CGSize(width: animation.size.width / scale, height: animation.size.height / scale)
        let points = drawing.zoom.longestDrawnSide(of: natural, in: drawing.cell)
        let pixels = (points * drawing.displayScale / 32).rounded(.up) * 32
        return pixels < max(animation.size.width, animation.size.height) ? pixels : nil
    }

    // MARK: Soak

    /// An hour of play with the wall rebuilt every minute and a memory warning
    /// every five, sampled every five seconds.
    struct Soak {
        static let duration: TimeInterval = 3600
        static let rebuildInterval: TimeInterval = 60
        static let warningInterval: TimeInterval = 300
        static let sampleInterval: TimeInterval = 5
        /// The sample drift is measured from: after the first minute, once
        /// the frames are decoded and the first rebuild is done.
        static let baselineTime: TimeInterval = 60

        let startedAt: ContinuousClock.Instant
        var elapsed: TimeInterval = 0
        var isRunning = true
        var samples: [Sample] = []
        var rebuildCount = 0
        /// When each memory warning was sent, for the charts to mark.
        var warnings: [TimeInterval] = []
        var decodedFrameCount = 0
        var lateFrameCount = 0
        var display = DemoDisplayMonitor.Figures()
        var lowestFramesPerSecond: Double?

        struct Sample {
            var time: TimeInterval
            var footprint: Int
            var poolCost: Int
            /// Players alive anywhere, against the cells on the wall: more
            /// means players that were let go are still around.
            var playerCount: Int
            var cellCount: Int
            var animationCount: Int
        }

        var baseline: Sample? {
            samples.first { $0.time >= Self.baselineTime }
        }

        var peakFootprint: Int {
            samples.map(\.footprint).max() ?? 0
        }

        var peakPoolCost: Int {
            samples.map(\.poolCost).max() ?? 0
        }
    }

    @ObservationIgnored private var soakCounts: [Cell.ID: (decoded: Int, late: Int)] = [:]
    /// Whether the soak turned the idle timer off, and so should turn it
    /// back on.
    @ObservationIgnored private var didDisableIdleTimer = false

    func startSoak() {
        soakCounts = [:]
        monitor.reset()
        soak = Soak(startedAt: .now)
        recordSoakCounts()
        appendSoakSample(at: 0)
        // An hour is longer than any auto-lock.
        if !UIApplication.shared.isIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = true
            didDisableIdleTimer = true
        }
    }

    func stopSoak() {
        guard soak?.isRunning == true else { return }
        soak?.isRunning = false
        if didDisableIdleTimer {
            UIApplication.shared.isIdleTimerDisabled = false
            didDisableIdleTimer = false
        }
    }

    private func advanceSoak(now: ContinuousClock.Instant) {
        guard var soak else { return }
        let elapsed = min(Soak.duration, (now - soak.startedAt).demoTimeInterval)
        let previous = soak.elapsed
        soak.elapsed = elapsed
        let counts = recordSoakCounts()
        soak.decodedFrameCount += counts.decoded
        soak.lateFrameCount += counts.late
        soak.display = monitor.figures
        if let fps = soak.display.framesPerSecond {
            soak.lowestFramesPerSecond = min(soak.lowestFramesPerSecond ?? fps, fps)
        }
        // At most one of each per second, however long the screen was away.
        if crossed(Soak.rebuildInterval, from: previous, to: elapsed), elapsed < Soak.duration {
            soak.rebuildCount += 1
            needsRebuild = true
            setNeedsUpdate()
        }
        if crossed(Soak.warningInterval, from: previous, to: elapsed), elapsed < Soak.duration {
            soak.warnings.append(elapsed)
            sendMemoryWarning()
        }
        self.soak = soak
        if crossed(Soak.sampleInterval, from: previous, to: elapsed) {
            appendSoakSample(at: elapsed)
        }
        if elapsed >= Soak.duration {
            stopSoak()
        }
    }

    private func crossed(_ interval: TimeInterval, from start: TimeInterval, to end: TimeInterval) -> Bool {
        (end / interval).rounded(.down) > (start / interval).rounded(.down)
    }

    private func appendSoakSample(at time: TimeInterval) {
        let pool = AnimatedImageFramePool.shared
        soak?.samples.append(Soak.Sample(
            time: time,
            footprint: DemoFootprint.read()?.footprint ?? 0,
            poolCost: pool.totalCost,
            playerCount: pool.playerCount,
            cellCount: cells.count,
            animationCount: pool.animationCount
        ))
    }

    /// The frames decoded and late since the last call, across the cells on
    /// the wall; a new cell counts from zero.
    @discardableResult
    private func recordSoakCounts() -> (decoded: Int, late: Int) {
        var total = (decoded: 0, late: 0)
        var counts: [Cell.ID: (decoded: Int, late: Int)] = [:]
        for (id, sample) in samples {
            let current = (decoded: sample.diagnostics.decodedFrameCount, late: sample.diagnostics.bufferMissCount)
            let last = soakCounts[id] ?? (0, 0)
            total.decoded += max(0, current.decoded - last.decoded)
            total.late += max(0, current.late - last.late)
            counts[id] = current
        }
        soakCounts = counts
        return total
    }
}

// MARK: - Choices

extension AnimationLabModel {
    enum ImageSet: CaseIterable, Identifiable {
        case formats
        case delays

        var id: Self { self }

        var title: String {
            switch self {
            case .formats: "Formats"
            case .delays: "Delays"
            }
        }

        var images: [DemoAnimation] {
            switch self {
            case .formats: DemoAnimation.formats
            case .delays: DemoAnimation.delays
            }
        }
    }

    enum TransformChoice: Hashable, CaseIterable {
        case none, tint, rounded, grayscale, alternating

        var title: String {
            switch self {
            case .none: "None"
            case .tint: "Tint"
            case .rounded: "Round"
            case .grayscale: "Gray"
            case .alternating: "Tint Every Other"
            }
        }

        /// The transform of the cell at the given index. Every other cell is
        /// tinted in the last choice, which splits each animation into two
        /// sets of frames.
        func frameTransform(at index: Int) -> AnimatedImageFrameTransform? {
            switch self {
            case .none: nil
            case .tint: .demoTint
            case .rounded: .demoRounded
            case .grayscale: .demoGrayscale
            case .alternating: index.isMultiple(of: 2) ? nil : .demoTint
            }
        }
    }

    enum FrameSize: Hashable, CaseIterable {
        /// The size the animation was authored at.
        case full
        /// The size the cell draws it at, in pixels.
        case cell

        var title: String {
            switch self {
            case .full: "Full"
            case .cell: "Cell"
            }
        }
    }

    static let playerBudgets: [Int?] = [nil, 256 * 1024, 512 * 1024, 1_048_576, 4 * 1_048_576, 16 * 1_048_576]

    static let counts = [1, 4, 9, 16, 25, 36]
}

/// How large a cell draws its animation: covering the cell, inside it, or a
/// multiple of the natural size, trimmed by the cell.
enum CellZoom: Hashable {
    case fill
    case fit
    case scale(Double)

    static let choices: [CellZoom] = [.fill, .fit, .scale(1), .scale(2), .scale(4), .scale(8)]

    var title: String {
        switch self {
        case .fill: "Fill"
        case .fit: "Fit"
        case .scale(let scale): "\(Int((scale * 100).rounded()))%"
        }
    }

    /// The longest side of an animation of the given natural size, in
    /// points, as a cell draws it.
    func longestDrawnSide(of natural: CGSize, in cell: CGSize) -> CGFloat {
        guard natural.width > 0, natural.height > 0 else { return 0 }
        let horizontal = cell.width / natural.width
        let vertical = cell.height / natural.height
        let scale = switch self {
        case .fill: max(horizontal, vertical)
        case .fit: min(horizontal, vertical)
        case .scale(let scale): CGFloat(scale)
        }
        return max(natural.width, natural.height) * scale
    }
}

// MARK: - Frame Transforms

/// The transforms the Lab offers, applied to every frame on the decoder. Each
/// one is a handful of Core Graphics calls, and the decode figures show what
/// they add.
extension AnimatedImageFrameTransform {
    /// Nuke pink over every frame, blended so the image shows through.
    static let demoTint = AnimatedImageFrameTransform(identifier: "demo.tint.pink") { frame in
        demoDrawnFrame(frame) { context, rect in
            context.draw(frame, in: rect)
            context.setFillColor(CGColor(srgbRed: 1, green: 0.18, blue: 0.33, alpha: 0.45))
            context.setBlendMode(.sourceAtop)
            context.fill(rect)
        }
    }

    /// The corners rounded off, an eighth of the short side.
    static let demoRounded = AnimatedImageFrameTransform(identifier: "demo.rounded.8th") { frame in
        demoDrawnFrame(frame) { context, rect in
            let radius = min(rect.width, rect.height) / 8
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.clip()
            context.draw(frame, in: rect)
        }
    }

    /// The frame redrawn into a one-channel gray bitmap, which is also a
    /// quarter of the memory per frame.
    static let demoGrayscale = AnimatedImageFrameTransform(identifier: "demo.grayscale") { frame in
        let context = CGContext(
            data: nil,
            width: frame.width, height: frame.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        guard let context else { return nil }
        context.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        return context.makeImage()
    }
}

/// Draws over or around the frame in a bitmap of the same size, in the format
/// the compositor likes.
private func demoDrawnFrame(_ frame: CGImage, _ draw: (CGContext, CGRect) -> Void) -> CGImage? {
    let space = frame.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: frame.width, height: frame.height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else { return nil }
    let rect = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
    draw(context, rect)
    return context.makeImage()
}
