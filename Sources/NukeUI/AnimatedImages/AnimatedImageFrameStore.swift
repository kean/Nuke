// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation

/// Identifies the decoded frames of one animation at one size.
///
/// ``AnimatedImagePlayer/Options/scale`` is not part of the key: it is applied
/// when a bitmap is wrapped in a platform image and never touches the pixels.
struct AnimatedImageFrameKey: Hashable {
    /// The pipeline parses an animation once and ``ImageCache`` holds the
    /// result, so every view showing the same image is handed the same
    /// instance, which makes identity the natural key.
    let source: ObjectIdentifier

    /// The longest side the frames are decoded at, or `nil` for the size the
    /// animation is stored at.
    let maxPixelSize: CGFloat?

    init(source: AnimatedImageSource, maxPixelSize: CGFloat?) {
        self.source = ObjectIdentifier(source)
        // A limit the animation already fits in downsamples nothing, so it is
        // spelled the same way as no limit: both views want the same frames.
        if let maxPixelSize, maxPixelSize > 0, maxPixelSize < max(source.size.width, source.size.height) {
            self.maxPixelSize = maxPixelSize
        } else {
            self.maxPixelSize = nil
        }
    }
}

/// The decoded frames of one animation at one size, shared by every player
/// showing it, and the single decoder that produces them.
///
/// Each player keeps its own playhead – its ``AnimatedImageFrameBuffer`` – and
/// the store holds the union of the windows those playheads ask for. When the
/// playheads coincide, the union is a single window. When they scatter across
/// an animation that doesn't fit, every member gets a smaller window so that
/// the total stays inside the share the pool gave the store. A store never
/// costs more than the whole animation, however many players draw from it.
@MainActor
final class AnimatedImageFrameStore {
    let key: AnimatedImageFrameKey
    let frameCount: Int

    /// The memory one decoded frame occupies, in bytes.
    let bytesPerFrame: Int

    /// Weak: the members hold the animation strongly, so the frames outlive
    /// the last player only as long as something else – ``ImageCache``, by
    /// way of the cached response – still holds the animation.
    private(set) weak var source: AnimatedImageSource?

    /// The memory the pool has allotted the store, in bytes.
    private(set) var allotment = 0

    /// The memory the frames it is holding occupy, in bytes.
    private(set) var byteCount = 0

    /// The number of players drawing from the store.
    var memberCount: Int { members.count { $0.buffer != nil } }

    /// The number of players filling a window of frames.
    var activeMemberCount: Int { members.count { $0.buffer?.fillsWindow == true } }

    /// `true` when no player is drawing from the store, which makes its frames
    /// the first thing the pool reclaims.
    var isIdle: Bool { memberCount == 0 }

    /// When a player last drew from the store, which orders the frames the
    /// pool gives back first.
    private(set) var lastUsed = monotonicTime()

    /// The decode in flight, if there is one.
    private(set) var currentDecode: Task<Void, Never>?

    private struct Frame {
        let image: CGImage
        let byteCount: Int
    }

    private struct Member {
        weak var buffer: AnimatedImageFrameBuffer?
    }

    private var frames: [Int: Frame] = [:]

    /// The frames the decoder refused, so that a truncated animation doesn't
    /// retry them forever.
    private var failedIndexes: Set<Int> = []

    private var members: [Member] = []

    /// Created on demand and dropped with the last member: a decoder holds the
    /// animation, and an idle store must not keep it alive.
    private var decoder: (any AnimatedImageFrameDecoding)?

    private var decodingIndex: Int?

    /// The members that wanted the frame in flight when it was scheduled.
    ///
    /// Captured then rather than read when the frame lands: a member that has
    /// moved past it still wants it (the late-frame path). A seek is what
    /// drops a member, and a decode nobody waits for is cancelled.
    private var decodingRequesters: Set<ObjectIdentifier> = []

    /// Weak: a player holds the store it plays from, so a store can outlive
    /// the pool that made it.
    private weak var pool: AnimatedImageFramePool?

    init(
        key: AnimatedImageFrameKey,
        source: AnimatedImageSource,
        pool: AnimatedImageFramePool,
        decoder: (any AnimatedImageFrameDecoding)? = nil
    ) {
        self.key = key
        self.source = source
        self.pool = pool
        self.frameCount = source.frameCount
        self.bytesPerFrame = AnimatedImageFrameStore.bytesPerFrame(for: source, maxPixelSize: key.maxPixelSize)
        self.decoder = decoder
    }

    /// Returns the memory one frame occupies when decoded no larger than the
    /// given size. Downsampling pays back the square of the scale.
    static func bytesPerFrame(for source: AnimatedImageSource, maxPixelSize: CGFloat?) -> Int {
        var bytesPerFrame = source.bytesPerFrame
        if let maxPixelSize, maxPixelSize > 0 {
            let longestSide = max(source.size.width, source.size.height)
            if longestSide > maxPixelSize {
                let scale = maxPixelSize / longestSide
                bytesPerFrame = Int(Double(bytesPerFrame) * Double(scale * scale))
            }
        }
        return bytesPerFrame
    }

    // MARK: Members

    func add(_ buffer: AnimatedImageFrameBuffer) {
        members.append(Member(buffer: buffer))
        lastUsed = monotonicTime()
        // Joins the decode in flight if it wants that frame, and asks for
        // nothing at all if the animation is already in memory.
        scheduleDecodeIfNeeded()
    }

    /// The frame a joining player should start on, or `nil` when nothing else
    /// is playing this animation.
    ///
    /// Starting there keeps a screen of the same animation to a single window
    /// of frames, and it is what a browser does with every `img` element
    /// showing one animation.
    func leadingIndex(excluding buffer: AnimatedImageFrameBuffer) -> Int? {
        liveMembers.first { $0 !== buffer && $0.fillsWindow }?.currentIndex
    }

    // MARK: Frames

    func frame(at index: Int) -> CGImage? {
        frames[index]?.image
    }

    /// `true` while the store still expects to produce the frame: it is
    /// neither decoded nor one the decoder has refused.
    func isPending(_ index: Int) -> Bool {
        frames[index] == nil && !failedIndexes.contains(index)
    }

    /// The number of decoded frames inside the given window.
    func decodedFrameCount(in window: Range<Int>) -> Int {
        indexes(in: window).count { frames[$0] != nil }
    }

    /// The memory the frames inside the given window occupy, in bytes.
    func byteCount(in window: Range<Int>) -> Int {
        indexes(in: window).reduce(0) { $0 + (frames[$1]?.byteCount ?? 0) }
    }

    /// Drops every decoded frame and stops the decode in flight.
    func removeAllFrames() {
        cancelDecode()
        frames.removeAll()
        byteCount = 0
    }

    /// Called by a member whenever its window moves or changes size.
    ///
    /// - parameter isSeeking: Whether the member moved somewhere the animation
    /// was not heading, which drops it from the decode in flight: that frame is
    /// for a place the playhead has left, and offering it would undo the seek.
    func didUpdateWindow(of buffer: AnimatedImageFrameBuffer, isSeeking: Bool) {
        if isSeeking {
            removeRequester(buffer)
        }
        evict()
        scheduleDecodeIfNeeded()
    }

    // MARK: Budget

    /// What the store would use if the pool had it to spare: every frame its
    /// members ask for between them, and never more than the whole animation.
    var demand: Int {
        let wanted = members.lazy.compactMap { $0.buffer?.wantedFrameCount }.reduce(0, +)
        return min(frameCount, wanted) * bytesPerFrame
    }

    /// Takes the share of the pool the store holds its frames in.
    func setAllotment(_ bytes: Int) {
        guard bytes != allotment else { return }
        let previous = windowLength
        allotment = bytes
        guard windowLength != previous else { return }
        evict()
        scheduleDecodeIfNeeded()
    }

    /// The number of frames each member may hold: the largest window such that
    /// the windows of every member together fit in the allotment.
    ///
    /// Members on the same frame share one window; the further apart they
    /// drift, the less each gets. Once the allotment covers the whole
    /// animation, every window is every frame.
    var windowLength: Int {
        let capacity = bytesPerFrame > 0 ? allotment / bytesPerFrame : frameCount
        guard capacity < frameCount else {
            return frameCount
        }
        let floor = AnimatedImageFrameBuffer.idleCapacity
        let playheads = Set(members.compactMap { $0.buffer?.currentIndex }).sorted()
        guard playheads.count > 1 else {
            return max(floor, capacity)
        }
        // The union grows with the window, so the largest window that fits is
        // a binary search away.
        var low = floor
        var high = max(floor, capacity)
        while low < high {
            let middle = (low + high + 1) / 2
            if unionSize(of: playheads, windowLength: middle) <= capacity {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    /// The number of distinct frames covered by a window of the given length
    /// starting at each playhead. A window reaches its full length or the next
    /// playhead, whichever comes first, so nothing is counted twice.
    private func unionSize(of playheads: [Int], windowLength: Int) -> Int {
        var total = 0
        for (offset, playhead) in playheads.enumerated() {
            let isLast = offset == playheads.count - 1
            let next = isLast ? playheads[0] + frameCount : playheads[offset + 1]
            total += min(windowLength, next - playhead)
        }
        return total
    }

    /// Drops the frames no member's window covers.
    ///
    /// An idle store keeps everything for a view that comes back on screen;
    /// the pool reclaims those frames when it needs the room.
    private func evict() {
        guard !members.isEmpty, !frames.isEmpty else { return }
        let windows = liveMembers.map { (start: $0.currentIndex, length: $0.capacity) }
        guard !windows.contains(where: { $0.length >= frameCount }) else {
            return // Some window covers the whole animation: nothing to evict
        }
        for (index, frame) in frames where !windows.contains(where: { covers(index, $0) }) {
            frames[index] = nil
            byteCount -= frame.byteCount
        }
    }

    private func covers(_ index: Int, _ window: (start: Int, length: Int)) -> Bool {
        (index - window.start + frameCount) % frameCount < window.length
    }

    /// Drops the frames outside every member's window, for the pool to call
    /// when it is over its limit.
    func reclaim() {
        if members.isEmpty {
            removeAllFrames()
        } else {
            evict()
        }
    }

    private func indexes(in window: Range<Int>) -> [Int] {
        window.map { $0 % frameCount }
    }

    // MARK: Decoding

    /// Starts decoding the frame the members need most, unless a decode is
    /// already in flight.
    ///
    /// Only one decode ever runs per animation: several at once would finish
    /// the frames needed last just as soon as the one needed next.
    func scheduleDecodeIfNeeded() {
        if let decodingIndex {
            // A member that has come to want the frame in flight waits for it.
            for buffer in liveMembers where buffer.wants(decodingIndex) {
                decodingRequesters.insert(ObjectIdentifier(buffer))
            }
            return
        }
        guard let index = nextNeededIndex(), let decoder = makeDecoderIfNeeded() else {
            return
        }
        decodingIndex = index
        decodingRequesters = Set(liveMembers.filter { $0.wants(index) }.map(ObjectIdentifier.init))
        currentDecode = Task(priority: priority(forFrameAt: index)) { [weak self] in
            let frame = await decoder.decode(at: index)
            // Checked before clearing the handle: a cancelled decode would
            // otherwise drop the handle of the decode that replaced it.
            guard let self, !Task.isCancelled else { return }
            self.currentDecode = nil
            self.decodingIndex = nil
            self.didDecode(frame, at: index)
            self.scheduleDecodeIfNeeded()
        }
    }

    /// The next frame worth decoding: the one a member is waiting on, then
    /// read-ahead a step at a time across every member.
    private func nextNeededIndex() -> Int? {
        let members = liveMembers
        if let index = members.first(where: { isPending($0.currentIndex) })?.currentIndex {
            return index
        }
        let longest = members.map(\.capacity).max() ?? 0
        for offset in 1..<max(1, longest) {
            for buffer in members where offset < buffer.capacity {
                let index = (buffer.currentIndex + offset) % frameCount
                if isPending(index) { return index }
            }
        }
        return nil
    }

    /// Only a frame a player is sitting on is urgent. Read-ahead at the main
    /// actor's priority would turn a grid of animations into CPU-bound decodes
    /// competing with the app's own work.
    private func priority(forFrameAt index: Int) -> TaskPriority {
        liveMembers.contains { $0.currentIndex == index } ? .userInitiated : .utility
    }

    private func didDecode(_ frame: AnimatedImageFrameDecoder.Frame?, at index: Int) {
        let requesters = decodingRequesters
        decodingRequesters = []
        guard let frame else {
            failedIndexes.insert(index)
            return
        }
        if frames[index] == nil {
            frames[index] = Frame(image: frame.image, byteCount: frame.byteCount)
            byteCount += frame.byteCount
        }
        for buffer in liveMembers where requesters.contains(ObjectIdentifier(buffer)) {
            // Offered even if the window moved past the frame: the player is
            // the one that knows whether it has anything better to show.
            buffer.storeDidDecodeFrame(at: index, duration: frame.duration)
        }
        evict()
        // The frames of an animation nobody plays aren't in the division of
        // the budget; this is where they stop being worth keeping.
        pool?.reclaimIfNeeded()
    }

    /// Drops a member from the decode in flight, cancelling it if the member
    /// was the last one waiting for it.
    private func removeRequester(_ buffer: AnimatedImageFrameBuffer) {
        decodingRequesters.remove(ObjectIdentifier(buffer))
        cancelDecodeIfUnwanted()
    }

    private func cancelDecodeIfUnwanted() {
        guard decodingIndex != nil else { return }
        decodingRequesters.formIntersection(liveMembers.map(ObjectIdentifier.init))
        guard decodingRequesters.isEmpty else { return }
        cancelDecode()
    }

    private func cancelDecode() {
        currentDecode?.cancel()
        currentDecode = nil
        decodingIndex = nil
        decodingRequesters = []
    }

    private func makeDecoderIfNeeded() -> (any AnimatedImageFrameDecoding)? {
        if let decoder { return decoder }
        guard let source else { return nil }
        let decoder = AnimatedImageFrameDecoder(source: source, maxPixelSize: key.maxPixelSize)
        self.decoder = decoder
        return decoder
    }

    private var liveMembers: [AnimatedImageFrameBuffer] {
        members.compactMap { $0.buffer }
    }

    /// Drops the members that have been released.
    func sweepMembers() {
        let count = members.count
        members.removeAll { $0.buffer == nil }
        guard members.count != count else { return }
        lastUsed = monotonicTime()
        if members.isEmpty {
            // A decoder holds the animation, and with it the encoded data.
            cancelDecode()
            decoder = nil
        }
        cancelDecodeIfUnwanted()
    }
}
