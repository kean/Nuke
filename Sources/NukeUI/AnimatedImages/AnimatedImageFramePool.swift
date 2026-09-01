// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// The memory every animation on screen shares for its decoded frames.
///
/// ``AnimatedImagePlayer/Options/maxBufferSize`` is per player, and a screen
/// full of animations that each took one would cost the sum of them. The pool
/// is the ceiling on that sum: every player draws its window from it, and the
/// more of them there are, the smaller the window each one gets.
///
/// ```swift
/// AnimatedImageFramePool.shared.costLimit = 32 * 1_048_576
/// ```
///
/// Nothing is divided until it has to be: while the animations together want
/// less than ``costLimit``, each one gets what it asked for. Past that, the
/// limit is split evenly, except that no animation is given more than it can
/// use – what a small one leaves goes to the ones that can fill it.
///
/// The budget is divided between animations, not players: every player showing
/// the same animation at the same size draws from one set of decoded frames,
/// so a screen of the same sticker costs one sticker. The frames of an
/// animation nothing is playing are kept until the pool needs the room, and go
/// for good when the animation itself does.
///
/// Two things are outside the limit. A player never holds fewer than two
/// frames, so a hundred animations at once will exceed any limit. And the pool
/// bounds the decoded frames, not the images the pipeline has cached, which is
/// ``ImageCache``.
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

    /// The memory the decoded frames occupy right now, in bytes. A frame two
    /// players are sharing is counted once.
    public var totalCost: Int {
        stores.values.reduce(0) { $0 + $1.byteCount }
    }

    /// The number of players drawing from the pool.
    public var playerCount: Int {
        stores.values.reduce(0) { $0 + $1.memberCount }
    }

    /// The number of players filling a window of frames.
    ///
    /// The rest are the ones nobody is watching, which hold the frame they are
    /// showing and the one after it. See ``AnimatedImagePlayer/keepsFullBuffer``.
    public var activePlayerCount: Int {
        stores.values.reduce(0) { $0 + $1.activeMemberCount }
    }

    /// The number of animations the players are drawing from, including the
    /// ones nobody is playing any more but whose frames are still kept.
    ///
    /// Lower than ``playerCount`` whenever the same animation is on screen
    /// more than once.
    public var animationCount: Int { stores.count }

    /// Returns a limit computed from the amount of physical memory on the
    /// device: 5% of it, capped at 128 MB.
    ///
    /// Decoded frames are the most expensive thing in an image library and the
    /// least valuable: a dropped frame costs milliseconds to decode again, and
    /// the encoded animation behind it is already in ``ImageCache``.
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

    /// The frames, one set per animation and size. Held strongly so that they
    /// outlive the players; each one holds its animation weakly, which keeps
    /// them from outliving it.
    private var stores: [AnimatedImageFrameKey: AnimatedImageFrameStore] = [:]

    /// Returns the frames of the given animation at the given size, creating
    /// them if this is the first player to ask.
    func store(
        for source: AnimatedImageSource,
        maxPixelSize: CGFloat?,
        decoder: (any AnimatedImageFrameDecoding)? = nil
    ) -> AnimatedImageFrameStore {
        let key = AnimatedImageFrameKey(source: source, maxPixelSize: maxPixelSize)
        // An animation that has been released can leave its address to the
        // next one, so identity alone isn't enough.
        if let store = stores[key], store.source === source {
            return store
        }
        let store = AnimatedImageFrameStore(key: key, source: source, pool: self, decoder: decoder)
        stores[key] = store
        return store
    }

    /// Divides the limit between the animations being played and hands each
    /// one its share.
    ///
    /// Called whenever what a player wants changes, not when frames are
    /// decoded or evicted: the division is of what the players ask for, or an
    /// animation filling its window would shrink the others as it went.
    func rebalance() {
        sweep()
        let registered = stores.values.map { (store: $0, demand: $0.demand) }
        guard !registered.isEmpty else { return }

        let total = registered.reduce(0) { $0 + $1.demand }
        if total > costLimit {
            // Max-min fair share: smallest demand first, with what each
            // animation leaves unused divided again between the rest.
            var remaining = max(0, costLimit)
            var share = registered.count
            var allotments: [(store: AnimatedImageFrameStore, bytes: Int)] = []
            for entry in registered.sorted(by: { $0.demand < $1.demand }) {
                let bytes = min(entry.demand, remaining / share)
                allotments.append((entry.store, bytes))
                remaining -= bytes
                share -= 1
            }
            // Applied only once every share is known: a store handed a
            // smaller window evicts frames on the spot.
            for allotment in allotments {
                allotment.store.setAllotment(allotment.bytes)
            }
        } else {
            for entry in registered {
                entry.store.setAllotment(entry.demand)
            }
        }
        reclaimIfNeeded()
    }

    /// Drops the animations nothing refers to any more, and the players that
    /// have been released.
    private func sweep() {
        stores = stores.filter { $0.value.source != nil }
        for store in stores.values {
            store.sweepMembers()
        }
    }

    /// Gives back the frames nobody's window covers until the pool is inside
    /// its limit again: the animations nobody is playing go first, least
    /// recently used first, then what the live ones hold outside their windows.
    func reclaimIfNeeded() {
        guard totalCost > costLimit else { return }
        for store in stores.values.filter(\.isIdle).sorted(by: { $0.lastUsed < $1.lastUsed }) {
            store.removeAllFrames()
            stores[store.key] = nil
            guard totalCost > costLimit else { return }
        }
        for store in stores.values {
            store.reclaim()
            guard totalCost > costLimit else { return }
        }
    }

    /// Asks for a division on the next turn of the main actor, for a buffer's
    /// `deinit`, which can't divide the budget itself.
    nonisolated func setNeedsRebalance() {
        Task { @MainActor in self.rebalance() }
    }
}
