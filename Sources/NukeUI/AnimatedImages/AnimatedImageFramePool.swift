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
/// ## What Is Shared
///
/// The budget is divided between animations, not between players. Every player
/// showing the same animation at the same size draws from a single set of
/// decoded frames – one decoder, one pile of bitmaps – so a screen of the same
/// sticker costs one sticker, and a view that comes back after scrolling away
/// finds the frames it left behind rather than decoding them again.
///
/// A share is only ever divided further when the players sharing an animation
/// have drifted apart *and* the whole of it doesn't fit: then each playhead
/// needs its own window and they split what the animation was given. Whatever
/// happens, one animation never costs more than the whole of it once.
///
/// The frames of an animation nothing is playing are kept until the pool needs
/// the room, and go as soon as the animation itself does: they belong to the
/// ``AnimatedImageSource`` the pipeline parsed, and last exactly as long as
/// something – ``ImageCache``, usually – still holds it.
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
    ///
    /// A frame two players are sharing is counted once, which is what it costs.
    public var totalCost: Int {
        stores.values.reduce(0) { $0 + $1.byteCount }
    }

    /// The number of players drawing from the pool.
    public var playerCount: Int {
        stores.values.reduce(0) { $0 + $1.memberCount }
    }

    /// The number of players filling a window of frames.
    ///
    /// The rest are the ones nobody is watching – a view that has scrolled off
    /// screen – which hold the frame they are showing and the one after it. See
    /// ``AnimatedImagePlayer/keepsFullBuffer``.
    public var activePlayerCount: Int {
        stores.values.reduce(0) { $0 + $1.activeMemberCount }
    }

    /// The number of animations the players are drawing from.
    ///
    /// Lower than ``playerCount`` whenever the same animation is on screen more
    /// than once, which is the case the sharing exists for. It counts the
    /// animations nobody is playing any more too, whose frames are being kept
    /// for a view that comes back to them.
    public var animationCount: Int { stores.count }

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

    /// The frames, one set per animation and size. Strongly, so that they
    /// outlive the players holding them; each one only holds its animation
    /// weakly, which is what keeps them from outliving it.
    private var stores: [AnimatedImageFrameKey: AnimatedImageFrameStore] = [:]

    /// Returns the frames of the given animation at the given size, creating
    /// them if this is the first player to ask.
    func store(
        for source: AnimatedImageSource,
        maxPixelSize: CGFloat?,
        decoder: (any AnimatedImageFrameDecoding)? = nil
    ) -> AnimatedImageFrameStore {
        let key = AnimatedImageFrameKey(source: source, maxPixelSize: maxPixelSize)
        // Identity is only as stable as the object it belongs to: an animation
        // that has been released can leave its address to the next one, and
        // handing that one the frames of the first would play the wrong
        // picture. Comparing the animations themselves settles it.
        if let store = stores[key], store.source === source {
            return store
        }
        let store = AnimatedImageFrameStore(key: key, source: source, pool: self, decoder: decoder)
        stores[key] = store
        return store
    }

    /// Divides the limit between the animations being played and hands each one
    /// its share.
    ///
    /// Called whenever what a player wants changes – it is created, released,
    /// starts or stops filling its window, or gives its frames back under
    /// memory pressure. Not when frames are decoded or evicted: the division is
    /// of what the players ask for, not of what they are holding, or an
    /// animation filling its window would shrink the others as it went.
    func rebalance() {
        sweep()
        let registered = stores.values.map { (store: $0, demand: $0.demand) }
        guard !registered.isEmpty else { return }

        let total = registered.reduce(0) { $0 + $1.demand }
        if total > costLimit {
            // An even split, smallest demand first, with what each animation
            // leaves unused divided again between the ones still to come. It is
            // the classic max-min share: the animations that fit are given
            // exactly what they need, and the ones that don't split the rest
            // evenly.
            var remaining = max(0, costLimit)
            var share = registered.count
            var allotments: [(store: AnimatedImageFrameStore, bytes: Int)] = []
            for entry in registered.sorted(by: { $0.demand < $1.demand }) {
                let bytes = min(entry.demand, remaining / share)
                allotments.append((entry.store, bytes))
                remaining -= bytes
                share -= 1
            }
            // Applied only once every share is known: an animation handed a
            // smaller window evicts frames on the spot, and doing that while the
            // division is half done would divide a limit that is still moving.
            for allotment in allotments {
                allotment.store.setAllotment(allotment.bytes)
            }
        } else {
            // There is enough for everybody, which is the case whenever a
            // screen isn't full of animations. Nobody is held to a share.
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

    /// Gives back the frames nobody's window covers, until the pool is inside
    /// its limit again.
    ///
    /// The frames of an animation nothing is playing are kept rather than
    /// dropped with the last player – that is what a view scrolling back to an
    /// animation it has already played finds – so they are what goes first, in
    /// the order they stopped being played in. What a live animation is holding
    /// outside its window goes next.
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

    /// Asks for a division on the next turn of the main actor.
    ///
    /// For a buffer's `deinit`, which is not on the main actor and so can't
    /// divide the budget itself. Everything else calls ``rebalance()`` and sees
    /// the result before it returns.
    nonisolated func setNeedsRebalance() {
        Task { @MainActor in self.rebalance() }
    }
}
