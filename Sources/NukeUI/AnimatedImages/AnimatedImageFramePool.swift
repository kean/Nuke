// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// The memory every animation on screen shares for its decoded frames.
///
/// A player keeps a window of decoded frames in memory, sized by
/// ``AnimatedImagePlayer/Options/maxBufferSize``. That budget is per player,
/// and a screen full of animations that each took one would cost the sum of
/// them: twenty animations at the default budget is 200 MB of bitmaps for
/// pictures that are a few kilobytes apiece on disk. The pool is the ceiling on
/// that sum. Every player draws its window from it, and the more of them there
/// are, the smaller the window each one gets – the total stays where it was
/// put, and the animation that got there first doesn't take the memory the
/// rest of the app needs.
///
/// ```swift
/// AnimatedImageFramePool.shared.costLimit = 32 * 1_048_576
/// ```
///
/// ## How the Budget Is Divided
///
/// Nothing is divided until it has to be: while the animations together want
/// less than ``costLimit``, each one is given what it asked for and the pool
/// changes nothing. Past that, the limit is split evenly, except that no player
/// is given more than it can use – what a small animation leaves on the table
/// goes to the ones that can fill it, rather than being held for an animation
/// that is already entirely in memory.
///
/// So four small stickers and one long, large GIF sharing 32 MB is not five
/// times 6.4 MB: the stickers take the 1 MB apiece they need, and the GIF plays
/// out of the remaining 28 MB.
///
/// Two things are outside the limit. A player never holds fewer than two frames
/// – with one, the next frame could only start decoding after the current one
/// was dropped – so a hundred animations at once will exceed any limit, at two
/// frames each. And the pool bounds the frames of the animations being played,
/// not the images the pipeline has cached, which is ``ImageCache``.
///
/// - note: Frames are not shared between players. Two views playing the same
/// animation decode it twice and hold it twice; what the pool bounds is the
/// total.
@MainActor
public final class AnimatedImageFramePool {
    /// The pool every player uses.
    public static let shared = AnimatedImageFramePool()

    /// The memory the decoded frames of every player may occupy, in bytes.
    ///
    /// Lowering it takes effect immediately: the players give back the frames
    /// that no longer fit and decode them again as the animations reach them.
    public var costLimit: Int {
        didSet {
            guard costLimit != oldValue else { return }
            rebalance()
        }
    }

    /// The memory the decoded frames occupy right now, in bytes.
    public var totalCost: Int {
        buffers.reduce(0) { $0 + ($1.buffer?.byteCount ?? 0) }
    }

    /// The number of players drawing from the pool.
    public var playerCount: Int {
        buffers.filter { $0.buffer != nil }.count
    }

    /// The number of players filling a window of frames.
    ///
    /// The rest are the ones nobody is watching – a view that has scrolled off
    /// screen – which hold the frame they are showing and the one after it. See
    /// ``AnimatedImagePlayer/keepsFullBuffer``.
    public var activePlayerCount: Int {
        buffers.filter { $0.buffer?.fillsWindow == true }.count
    }

    /// Returns a limit computed from the amount of physical memory on the
    /// device: 5% of it, capped at 128 MB.
    ///
    /// Decoded frames are the most expensive thing in an image library and the
    /// least valuable: a frame that is dropped costs a decode to get back,
    /// which is milliseconds, where the encoded animation behind it is already
    /// in ``ImageCache``. So the share here is a third of what that cache
    /// takes.
    public static var defaultCostLimit: Int {
        let calculated = Int(Double(ProcessInfo.processInfo.physicalMemory) * 0.05)
        return min(calculated, 134_217_728) // 128 MB
    }

    /// Creates a pool with the given limit.
    ///
    /// - parameter costLimit: The memory the decoded frames may occupy, in
    /// bytes. ``defaultCostLimit`` by default.
    public init(costLimit: Int = AnimatedImageFramePool.defaultCostLimit) {
        self.costLimit = costLimit
    }

    /// The buffers, weakly: a buffer is owned by its player, and a player that
    /// is released takes its frames with it. The dead entries are swept the
    /// next time the budget is divided.
    private var buffers: [Entry] = []

    private struct Entry {
        weak var buffer: AnimatedImageFrameBuffer?
    }

    func register(_ buffer: AnimatedImageFrameBuffer) {
        buffers.append(Entry(buffer: buffer))
        rebalance()
    }

    /// Divides the limit between the registered buffers and hands each one its
    /// share.
    ///
    /// Called whenever what a buffer wants changes – it is created, released,
    /// starts or stops filling its window, or gives its frames back under
    /// memory pressure. Not when frames are decoded or evicted: the division is
    /// of what the buffers ask for, not of what they are holding, or a buffer
    /// filling its window would shrink the others as it went.
    func rebalance() {
        buffers.removeAll { $0.buffer == nil }
        let registered = buffers.compactMap(\.buffer).map { (buffer: $0, demand: $0.demand) }
        guard !registered.isEmpty else { return }

        let total = registered.reduce(0) { $0 + $1.demand }
        guard total > costLimit else {
            // There is enough for everybody, which is the case whenever a
            // screen isn't full of animations. Nobody is held to a share.
            for entry in registered {
                entry.buffer.setAllotment(entry.demand)
            }
            return
        }

        // An even split, smallest demand first, with what each buffer leaves
        // unused divided again between the ones still to come. It is the
        // classic max-min share: the animations that fit are given exactly what
        // they need, and the ones that don't split the rest evenly.
        var remaining = max(0, costLimit)
        var share = registered.count
        var allotments: [(buffer: AnimatedImageFrameBuffer, bytes: Int)] = []
        for entry in registered.sorted(by: { $0.demand < $1.demand }) {
            let bytes = min(entry.demand, remaining / share)
            allotments.append((entry.buffer, bytes))
            remaining -= bytes
            share -= 1
        }
        // Applied only once every share is known: a buffer handed a smaller
        // window evicts frames on the spot, and doing that while the division
        // is half done would divide a limit that is still moving.
        for allotment in allotments {
            allotment.buffer.setAllotment(allotment.bytes)
        }
    }

    /// Asks for a division on the next turn of the main actor.
    ///
    /// For a buffer's `deinit`, which is not on the main actor and so can't
    /// divide the budget itself. Everything else calls ``rebalance()`` and sees
    /// the result before it returns.
    nonisolated func setNeedsRebalance() {
        Task { @MainActor in self.rebalance() }
    }
}
