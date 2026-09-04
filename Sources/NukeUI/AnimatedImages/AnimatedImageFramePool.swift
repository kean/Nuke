// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

#if canImport(UIKit)
import UIKit
#endif

/// The memory every animation on screen shares for its decoded frames.
///
/// An animation alone may take all of it. A screen full of them draws from it
/// together, and the pool holds as many of them whole as fit, smallest first;
/// the rest play out of a window of a few frames, decoded as they go.
///
/// ```swift
/// AnimatedImageFramePool.shared.costLimit = 32 * 1_048_576
/// ```
///
/// See <doc:AnimatedImages> for how the budget is divided, what sits outside
/// it, and how the pool answers a memory warning.
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
    /// showing and the one after it.
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
    /// It is a quarter of the one budget decoded images get, and
    /// ``Nuke/ImageCache/defaultCostLimit`` is the other three quarters: the
    /// two caches split one figure, so playing animations doesn't raise what
    /// an app's images may cost in memory.
    public static var defaultCostLimit: Int {
        min(ImageCache.defaultMemoryBudget / 4, 134_217_728) // 128 MB
    }

    /// Creates a pool with the given limit.
    ///
    /// - parameter costLimit: The memory the decoded frames may occupy, in
    /// bytes. ``defaultCostLimit`` by default.
    public init(costLimit: Int = AnimatedImageFramePool.defaultCostLimit) {
        self.costLimit = costLimit
        registerForApplicationNotifications()
    }

    // No `deinit`: the pool every player uses lives for the process, so the
    // notification subscriptions it takes are never worth taking back.

    // MARK: Memory Pressure

    /// Gives back the frames of every animation nobody is playing and holds
    /// the ones being played at the two frames playback needs.
    ///
    /// Called automatically on a memory warning. Playback continues, and the
    /// windows go back to the size the pool gave them once the pressure has
    /// had time to pass.
    public func reduceMemoryUsage() {
        isUnderMemoryPressure = true
        // Every store is handed a new share, which is what drops the frames
        // that no longer fit, and the animations nobody is playing are dropped
        // whole. Answered on every warning rather than only the first: a
        // second one is asking for whatever has gone idle since.
        rebalance()
        // A memory warning arrives while the app is active, usually on the very
        // screen the animation is on. Waiting for a trip to the background
        // would keep an animation that is up all session re-decoding every
        // frame for the rest of it.
        restore?.cancel()
        restore = Task { [weak self, memoryPressureGracePeriod] in
            try? await Task.sleep(for: .seconds(memoryPressureGracePeriod))
            guard !Task.isCancelled else { return }
            self?.endMemoryPressure()
        }
    }

    /// Gives back the frames of every animation nobody is playing.
    ///
    /// Called when the app goes to the background, where ``Nuke/ImageCache``
    /// trims itself for the same reason: nothing is on screen, so the frames
    /// kept for a view that might come back are a cache the app isn't using,
    /// and the animations they came from are on their way out of the cache
    /// anyway. The players that are still around keep the two frames they need
    /// to resume without a stall.
    public func removeIdleAnimations() {
        sweep()
        for store in stores.values.filter(\.isIdle) {
            remove(store)
        }
    }

    /// `true` while every animation is held at its two-frame floor and the
    /// frames of the ones nobody is playing are kept no longer.
    private(set) var isUnderMemoryPressure = false

    /// How long the animations stay shrunk after a memory warning: long enough
    /// for the pressure to pass, short enough that an animation on screen all
    /// session doesn't re-decode every frame for the rest of it. The tests
    /// shorten it.
    var memoryPressureGracePeriod: TimeInterval = 60

    private var restore: Task<Void, Never>?

    private func endMemoryPressure() {
        guard isUnderMemoryPressure else { return }
        isUnderMemoryPressure = false
        // Every store is handed a new share, which is what starts refilling
        // the windows now the ceiling has come off.
        rebalance()
    }

    private func registerForApplicationNotifications() {
#if os(iOS) || os(tvOS) || os(visionOS)
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reduceMemoryUsage() }
        }
        // Coming back to the foreground is the clearest signal that the memory
        // pressure is over.
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restore?.cancel()
                self?.endMemoryPressure()
            }
        }
        // Nothing is on screen, and a store whose animation the cache has just
        // let go of is otherwise held until something else makes the pool look.
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeIdleAnimations() }
        }
#endif
    }

    // MARK: Stores

    /// The frames, one set per animation and size. Held strongly so that they
    /// outlive the players; each one holds its animation weakly, which keeps
    /// them from outliving it.
    private var stores: [AnimatedImageFrameKey: AnimatedImageFrameStore] = [:]

    /// Returns the frames of the given animation at the given size, creating
    /// them if this is the first player to ask.
    func store(
        for source: AnimatedImageSource,
        maxPixelSize: CGFloat?,
        transform: AnimatedImageFrameTransform? = nil,
        decoder: (any AnimatedImageFrameDecoding)? = nil
    ) -> AnimatedImageFrameStore {
        let key = AnimatedImageFrameKey(source: source, maxPixelSize: maxPixelSize, transform: transform)
        // The usual case: another view of the same animation at the same size.
        // An animation that has been released can leave its address to the
        // next one, so identity alone isn't enough.
        if let store = stores[key], store.source === source {
            return store
        }
        if let store = largerStore(for: key, source: source) {
            return store
        }
        let store = AnimatedImageFrameStore(key: key, source: source, pool: self, transform: transform, decoder: decoder)
        stores[key] = store
        return store
    }

    /// Returns the smallest set of frames already being decoded for the same
    /// animation and transform at a size that covers the one asked for and is
    /// not too much larger than it, if there is one.
    ///
    /// A frame decoded for a larger view answers a smaller one – the view
    /// scales it as it draws it – so a grid whose cells differ by a size
    /// step, or the same sticker drawn a little smaller in one place than
    /// another, is decoded and held once rather than twice. The smaller view pays for it
    /// in bytes: it holds the larger view's frames, and goes on holding them
    /// after that view has gone, which is what ``maxSharedSizeRatio`` bounds.
    ///
    /// The reuse only reaches backwards. A view that wants more than anything
    /// decoded so far starts a set of its own, and the smaller sets already
    /// being played stay where they are: the players holding them can't be
    /// moved to another set, and dropping frames a view is playing from to
    /// decode larger ones would stall it.
    private func largerStore(for key: AnimatedImageFrameKey, source: AnimatedImageSource) -> AnimatedImageFrameStore? {
        let wanted = decodedSize(key.maxPixelSize, of: source)
        let limit = wanted * Self.maxSharedSizeRatio
        return stores.values
            // An animation that has been released can leave its address to
            // the next one, so identity alone isn't enough.
            .filter { $0.source === source && $0.key.transform == key.transform }
            .filter { (wanted...limit).contains(decodedSize($0.key.maxPixelSize, of: source)) }
            .min { decodedSize($0.key.maxPixelSize, of: source) < decodedSize($1.key.maxPixelSize, of: source) }
    }

    /// The most a set of frames may exceed the size a view asked for and still
    /// answer it: twice the longest side, which is four times the pixels.
    ///
    /// A view that joins a larger set doesn't decode the animation a second
    /// time, and pays for that in bytes – so what it saves has to be worth
    /// what it costs. Unbounded, a 44-point avatar that appears after a
    /// full-screen view of the same animation would hold 1024-pixel frames for
    /// the rest of its life, at the large view's bytes in the pool's division
    /// and the large view's cost per frame whenever the animation is windowed,
    /// long after that view has gone. Views closer than this mostly round to
    /// one size to begin with and share exactly.
    private static let maxSharedSizeRatio: CGFloat = 2

    /// The longest side a set of frames is decoded at: the limit its key
    /// holds, or the animation's own longest side for the key of a set decoded
    /// at the size the animation is stored at – which a key spells every limit
    /// the animation already fits in as, and which is therefore larger than
    /// any limit a key keeps.
    private func decodedSize(_ maxPixelSize: CGFloat?, of source: AnimatedImageSource) -> CGFloat {
        maxPixelSize ?? max(source.size.width, source.size.height)
    }

    /// Divides the limit between the animations being played and hands each
    /// one its share.
    ///
    /// Called whenever what a player wants changes, not when frames are
    /// decoded or evicted: the division is of what the players ask for, or an
    /// animation filling its window would shrink the others as it went.
    func rebalance() {
        rebalanceCount += 1
        sweep()
        // Nothing is worth caching while the system is short of memory: the
        // animations nobody is playing go whole rather than down to the floor
        // the live ones are held at, and one that goes idle during the grace
        // period goes with them.
        if isUnderMemoryPressure {
            for store in stores.values.filter(\.isIdle) {
                remove(store)
            }
        }
        guard !stores.isEmpty else { return }
        // Applied only once every share is known: a store handed a smaller
        // window evicts frames on the spot.
        for share in divide(costLimit, between: Array(stores.values)) {
            share.store.setAllotment(share.bytes, least: share.least)
        }
        reclaimIfNeeded()
    }

    private struct Share {
        let store: AnimatedImageFrameStore
        /// What the store needs to hold its animation whole.
        let demand: Int
        /// What it needs to play the animation out of a window.
        let least: Int
        var bytes = 0
    }

    /// Returns what each store gets of the given limit: as many of the
    /// animations whole as fit, smallest first, and a window of the read-ahead
    /// to the rest.
    ///
    /// There are two amounts worth giving an animation – enough to hold it
    /// whole, and enough for a window of the read-ahead – because anything in
    /// between re-decodes every frame each loop all the same. So every store
    /// gets its window first, and what is left holds animations whole from the
    /// smallest up, which fits as many of them as anything could. An even split
    /// would hold nothing whole the moment the animations together outgrew the
    /// limit.
    private func divide(_ limit: Int, between stores: [AnimatedImageFrameStore]) -> [Share] {
        var shares = stores.map { Share(store: $0, demand: $0.demand, least: $0.leastDemand) }
        var remaining = max(0, limit)

        // The windows, max-min fair: smallest first, with what one leaves
        // unused divided again between the rest. They only come up short when
        // even the windows together don't fit.
        var count = shares.count
        for index in shares.indices.sorted(by: { shares[$0].least < shares[$1].least }) {
            let bytes = min(shares[index].least, remaining / count)
            shares[index].bytes = bytes
            remaining -= bytes
            count -= 1
        }

        // Then whole animations out of what is left. When two the same size
        // compete for the last of it, the one already whole keeps its frames
        // rather than trading places with a newcomer, and after that the one
        // that has been playing longer goes first.
        let order = shares.indices.sorted { lhs, rhs in
            if shares[lhs].demand != shares[rhs].demand {
                return shares[lhs].demand < shares[rhs].demand
            }
            let lhsIsWhole = shares[lhs].store.allotment >= shares[lhs].demand
            let rhsIsWhole = shares[rhs].store.allotment >= shares[rhs].demand
            if lhsIsWhole != rhsIsWhole {
                return lhsIsWhole
            }
            return shares[lhs].store.lastUsed < shares[rhs].store.lastUsed
        }
        for index in order {
            let cost = shares[index].demand - shares[index].bytes
            guard cost <= remaining else { continue }
            shares[index].bytes = shares[index].demand
            remaining -= cost
        }
        return shares
    }

    /// Drops the animations nothing refers to any more, and the players that
    /// have been released.
    private func sweep() {
        // The members first: a store that has just lost its last one lets go of
        // its decoder, and with it the last reference to an animation nothing
        // else holds, which is what the filter then sees.
        for store in stores.values {
            store.sweepMembers()
        }
        stores = stores.filter { $0.value.source != nil }
    }

    /// Gives back the frames nobody's window covers until the pool is inside
    /// its limit again: the animations nobody is playing go first, least
    /// recently used first, then what the live ones hold outside their windows.
    func reclaimIfNeeded() {
        guard totalCost > costLimit else { return }
        for store in stores.values.filter(\.isIdle).sorted(by: { $0.lastUsed < $1.lastUsed }) {
            remove(store)
            guard totalCost > costLimit else { return }
        }
        for store in stores.values {
            store.reclaim()
            guard totalCost > costLimit else { return }
        }
    }

    /// Drops an animation's frames along with the store holding them.
    private func remove(_ store: AnimatedImageFrameStore) {
        store.removeAllFrames()
        stores[store.key] = nil
    }

    /// The number of divisions the pool has run, which is what tells one
    /// division of a screenful of players from a screenful of divisions.
    private(set) var rebalanceCount = 0

    /// Asks for a division on the next turn of the main actor, for a player's
    /// `deinit`, which can't divide the budget itself.
    ///
    /// One division answers however many players ask for it: a list scrolling
    /// releases a screenful of them in a single turn, and dividing the budget
    /// walks every animation in the pool, so asking once per player would walk
    /// them all once per released cell to reach the same answer.
    nonisolated func setNeedsRebalance() {
        let wasScheduled = isRebalanceScheduled.withLock { scheduled in
            defer { scheduled = true }
            return scheduled
        }
        guard !wasScheduled else { return }
        Task { @MainActor in
            // Before the division, not after: a player released while it runs
            // is one the division it asked for has not seen.
            self.isRebalanceScheduled.withLock { $0 = false }
            self.rebalance()
        }
    }

    /// Whether a division is already on its way. Behind a lock rather than on
    /// the main actor, because a `deinit` is on whatever thread released the
    /// player.
    private nonisolated let isRebalanceScheduled = OSAllocatedUnfairLock(initialState: false)
}
