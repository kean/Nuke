// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation

/// Identifies the decoded frames of one animation at one size.
///
/// A decoded frame is a pure function of the animation, the frame index, and
/// the size it is decoded at, so two players that agree on those three share
/// every frame between them.
///
/// ``AnimatedImagePlayer/Options/scale`` is deliberately not part of it: it is
/// applied when a bitmap is wrapped in a `UIImage` or an `NSImage` and never
/// touches the pixels, so a player reporting its frames at a different scale
/// still shares them.
struct AnimatedImageFrameKey: Hashable {
    /// The identity of the animation.
    ///
    /// The pipeline parses an animation once and ``ImageCache`` holds the
    /// result, so every view showing the same image is handed the same
    /// instance – which makes identity the natural key, and its lifetime the
    /// natural lifetime for the frames decoded from it.
    let source: ObjectIdentifier

    /// The longest side the frames are decoded at, or `nil` for the size the
    /// animation is stored at.
    let maxPixelSize: CGFloat?

    init(source: AnimatedImageSource, maxPixelSize: CGFloat?) {
        self.source = ObjectIdentifier(source)
        // A limit the animation is already inside of downsamples nothing, so
        // it is spelled the same way as no limit at all: a view that worked
        // one out and a view that didn't ask for one are looking at the same
        // pixels and should be looking at the same frames.
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
/// A frame is an immutable, reference-counted `CGImage`, so handing the same
/// one to twenty views costs twenty pointers. What used to cost twenty times
/// was everything around it: twenty decoders walking the same container,
/// twenty sliding windows over the same frames, and twenty shares of the
/// memory ``AnimatedImageFramePool`` divides. A store is where all three
/// become one.
///
/// Each player keeps its own playhead – its own ``AnimatedImageFrameBuffer`` –
/// and the store holds the union of the windows those playheads ask for. When
/// the playheads coincide, which is the usual case for a screen of the same
/// sticker, the union is a single window. When they scatter and the whole
/// animation doesn't fit, the union grows, and the store hands every member a
/// smaller window so that the total stays inside the share the pool gave it.
/// Either way a store never costs more than the whole animation, however many
/// players draw from it.
@MainActor
final class AnimatedImageFrameStore {
    let key: AnimatedImageFrameKey
    let frameCount: Int

    /// The memory one decoded frame occupies, at the size this store decodes
    /// at.
    let bytesPerFrame: Int

    /// The animation the frames come from, weakly.
    ///
    /// A member holds it strongly, so it is always there while anything is
    /// playing. Once the last one goes, the frames outlive it only as long as
    /// something else – ``ImageCache``, by way of the response the view was
    /// given – still wants the animation, which is exactly as long as they are
    /// worth keeping: a view that comes back finds them, and an animation
    /// nothing references any more could not be decoded further anyway.
    private(set) weak var source: AnimatedImageSource?

    /// The memory the pool has allotted the store, in bytes.
    private(set) var allotment = 0

    /// The memory the frames it is holding occupy, in bytes.
    private(set) var byteCount = 0

    /// The number of players drawing from the store.
    var memberCount: Int { members.count { $0.buffer != nil } }

    /// The number of players filling a window of frames.
    var activeMemberCount: Int { members.count { $0.buffer?.fillsWindow == true } }

    /// `true` when no player is drawing from the store any more. Its frames
    /// are then the first thing the pool reclaims.
    var isIdle: Bool { memberCount == 0 }

    /// When a player last drew from the store, which is what orders the frames
    /// the pool gives back first.
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

    /// The frames the decoder refused. Without this, a truncated animation
    /// would put the store in a loop, retrying the frame it can never produce.
    private var failedIndexes: Set<Int> = []

    private var members: [Member] = []

    /// Built on demand and dropped when the last member goes: a decoder holds
    /// the animation, and an idle store holds nothing that would keep one
    /// alive.
    private var decoder: (any AnimatedImageFrameDecoding)?

    private var decodingIndex: Int?

    /// The members that wanted the frame being decoded when it was scheduled.
    ///
    /// Captured then rather than read when it lands, because a player that has
    /// run past the frame in the meantime still wants it – that is the whole
    /// of the late-frame path. What does drop a member is a seek, which is the
    /// one move that says the frame is for somewhere the playhead has left; a
    /// decode nobody is waiting for any more is cancelled.
    private var decodingRequesters: Set<ObjectIdentifier> = []

    /// Weakly: the pool owns its stores, but a player holds the one it is
    /// playing from, so a store can outlive the pool it was made by.
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

    /// Returns the memory one decoded frame occupies when decoded no larger
    /// than the given size.
    ///
    /// Frames are decoded into bitmaps with 8 bits per component, so the figure
    /// depends only on the size, not on how well the image compresses – and
    /// downsampling pays back the square of the scale.
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
        // A player that arrives while a frame it wants is already being decoded
        // waits for that one rather than asking for it again – and one that
        // arrives to an animation already in memory asks for nothing at all.
        scheduleDecodeIfNeeded()
    }

    /// The frame a player joining the store should start on, or `nil` when
    /// nothing else is playing this animation.
    ///
    /// Starting there rather than at the beginning is what keeps a screen of
    /// the same sticker to a single window of frames – and it is what a browser
    /// does, where every `img` element on one animation is driven by the same
    /// decoded stream and so plays in lockstep.
    func leadingIndex(excluding buffer: AnimatedImageFrameBuffer) -> Int? {
        liveMembers.first { $0 !== buffer && $0.fillsWindow }?.currentIndex
    }

    // MARK: Frames

    func frame(at index: Int) -> CGImage? {
        frames[index]?.image
    }

    /// `true` while the store still expects to produce the frame at the given
    /// index: it is neither decoded nor one the decoder has refused.
    func isPending(_ index: Int) -> Bool {
        frames[index] == nil && !failedIndexes.contains(index)
    }

    /// The number of frames held inside the given window.
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
    /// - parameter isSeeking: Whether the member is being moved somewhere the
    /// animation was not heading, which drops it from the decode in flight.
    /// That frame is for a place its playhead has left, and offering it would
    /// tell the player about a frame nobody asked for – with a sliding window,
    /// where the frame a seek lands on is almost never decoded already, that
    /// undid every seek.
    func didUpdateWindow(of buffer: AnimatedImageFrameBuffer, isSeeking: Bool) {
        if isSeeking {
            removeRequester(buffer)
        }
        evict()
        scheduleDecodeIfNeeded()
    }

    // MARK: Budget

    /// What the store would use if the pool had it to spare: enough for every
    /// frame its members between them are asking for, and never more than the
    /// whole animation however many of them there are.
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

    /// The number of frames each member may hold.
    ///
    /// The share the pool gave the store buys a number of frames; this is how
    /// many of them one window can be, so that the windows of every member
    /// together stay inside it. When they all sit on the same frame, one window
    /// is the whole share; the further apart they drift, the less each of them
    /// gets – and none of it matters at all once the share covers the whole
    /// animation, which is when every window is every frame.
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
        // a binary search away rather than a walk.
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
    /// starting at each of the given playheads.
    ///
    /// A window reaches either its full length or the next playhead, whichever
    /// comes first – everything past that is covered by the window starting
    /// there – so the gaps add up to the union with nothing counted twice.
    private func unionSize(of playheads: [Int], windowLength: Int) -> Int {
        var total = 0
        for (offset, playhead) in playheads.enumerated() {
            let isLast = offset == playheads.count - 1
            let next = isLast ? playheads[0] + frameCount : playheads[offset + 1]
            total += min(windowLength, next - playhead)
        }
        return total
    }

    /// Drops the frames no member's window covers any more.
    ///
    /// An idle store keeps everything: its frames are what a view coming back
    /// on screen finds instead of decoding the animation again, and the pool
    /// reclaims them when it needs the room.
    private func evict() {
        guard !members.isEmpty, !frames.isEmpty else { return }
        let windows = liveMembers.map { (start: $0.currentIndex, length: $0.capacity) }
        guard !windows.contains(where: { $0.length >= frameCount }) else {
            // Somebody's window is the whole animation, so every frame is in
            // one: never evict, never re-decode. The case worth being quick
            // about, because it is the one a screen of stickers is in.
            return
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

    /// Starts decoding the frame the store's members need most, if there is
    /// one and nothing is being decoded already.
    ///
    /// Only one decode is ever in flight per animation, whatever the number of
    /// players: they are all asking the same decoder for the same frames, and
    /// running several at once would finish the frames that are needed last
    /// just as soon as the one that is needed next.
    func scheduleDecodeIfNeeded() {
        if let decodingIndex {
            // A member that has come to want the frame being decoded waits for
            // it rather than asking for it again.
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
            // The cancellation check comes first: clearing the handle from a
            // cancelled decode would drop the handle of the decode that started
            // in its place and let a third one begin alongside it.
            guard let self, !Task.isCancelled else { return }
            self.currentDecode = nil
            self.decodingIndex = nil
            self.didDecode(frame, at: index)
            self.scheduleDecodeIfNeeded()
        }
    }

    /// The next frame worth decoding, in the order the store's members need
    /// them.
    private func nextNeededIndex() -> Int? {
        let members = liveMembers.filter(\.isDecodingEnabled)
        // The frame a player is waiting on comes first: there is nothing for it
        // to show until that one lands.
        for buffer in members where isPending(buffer.currentIndex) {
            return buffer.currentIndex
        }
        // The rest is read-ahead, taken a step at a time across every member so
        // that no window is filled to its end while another has yet to start.
        let longest = members.map(\.capacity).max() ?? 0
        for offset in 1..<max(1, longest) {
            for buffer in members where offset < buffer.capacity {
                let index = (buffer.currentIndex + offset) % frameCount
                if isPending(index) { return index }
            }
        }
        return nil
    }

    /// The priority to decode the frame at the given index at.
    ///
    /// Only a frame some player is sitting on is urgent. Everything else is
    /// read-ahead, and read-ahead at the priority the main actor hands down is
    /// what turns a grid of animations into a pile of CPU-bound decodes
    /// competing with the app's own async work on a pool about as wide as the
    /// core count.
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
            // The window may have moved past the frame while it was being
            // decoded. It is offered anyway: the player is the one that knows
            // whether it has anything better to show, and it moves its window
            // back if it doesn't.
            buffer.storeDidDecodeFrame(at: index, duration: frame.duration)
        }
        // Whatever the players decided, the frame is over the budget by now if
        // it is still outside every window.
        evict()
        // The budget is divided between what the players ask for, and the
        // frames of an animation nobody is playing any more aren't in that
        // division – they are kept on the chance a view comes back to them.
        // This is where they stop being worth keeping.
        pool?.reclaimIfNeeded()
    }

    /// Drops a member from the decode in flight, cancelling it if it was the
    /// last one waiting for it.
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

    /// Called by a member that has stopped decoding: it is no longer waiting
    /// for the frame in flight, and the decode is dropped if nothing else is.
    func memberDidStopDecoding(_ buffer: AnimatedImageFrameBuffer) {
        removeRequester(buffer)
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
            // Nothing is playing this animation any more, and a decoder holds
            // it: keeping one would pin the animation, and with it the encoded
            // data, for as long as the store held a single frame.
            cancelDecode()
            decoder = nil
        }
        cancelDecodeIfUnwanted()
    }
}
