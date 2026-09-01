// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

#if canImport(UIKit)
import UIKit
#endif

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
        registerForApplicationNotifications()
    }

    // No `deinit`: the pool every player uses lives for the process, so the
    // notification subscriptions it takes are never worth taking back.

    // MARK: Memory Pressure

    /// Holds every animation at the two frames playback needs, dropping the
    /// decoded frames that no longer fit.
    ///
    /// Called automatically on a memory warning. Playback continues, and the
    /// windows go back to the size the pool gave them once the pressure has
    /// had time to pass.
    public func reduceMemoryUsage() {
        setUnderMemoryPressure(true)
        // A memory warning arrives while the app is active, usually on the very
        // screen the animation is on. Waiting for a trip to the background
        // would keep an animation that is up all session re-decoding every
        // frame for the rest of it.
        restore?.cancel()
        restore = Task { [weak self, memoryPressureGracePeriod] in
            try? await Task.sleep(for: .seconds(memoryPressureGracePeriod))
            guard !Task.isCancelled else { return }
            self?.setUnderMemoryPressure(false)
        }
    }

    /// `true` while every animation is held at its two-frame floor.
    private(set) var isUnderMemoryPressure = false

    /// How long the animations stay shrunk after a memory warning: long enough
    /// for the pressure to pass, short enough that an animation on screen all
    /// session doesn't re-decode every frame for the rest of it. The tests
    /// shorten it.
    var memoryPressureGracePeriod: TimeInterval = 60

    private var restore: Task<Void, Never>?

    private func setUnderMemoryPressure(_ isUnderPressure: Bool) {
        guard isUnderMemoryPressure != isUnderPressure else { return }
        isUnderMemoryPressure = isUnderPressure
        // Every store is handed a new share, which is what drops the frames
        // that no longer fit and starts refilling when the ceiling comes off.
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
                self?.setUnderMemoryPressure(false)
            }
        }
#endif
    }

    // MARK: Stores

    /// The frames, one set per animation and size. Held strongly so that they
    /// outlive the players; each one holds its animation weakly, which keeps
    /// them from outliving it.
    private var stores: [AnimatedImageFrameKey: AnimatedImageFrameStore] = [:]

    /// The registry the stores pick their decoders from. The shared one unless
    /// a test replaces it.
    var decoderRegistry: AnimatedImageFrameDecoderRegistry = .shared

    /// Returns the frames of the given animation at the given size, creating
    /// them if this is the first player to ask.
    func store(
        for source: AnimatedImageSource,
        maxPixelSize: CGFloat?,
        transform: AnimatedImageFrameTransform? = nil,
        decoder: (any AnimatedImageFrameDecoding)? = nil
    ) -> AnimatedImageFrameStore {
        let key = AnimatedImageFrameKey(source: source, maxPixelSize: maxPixelSize, transform: transform)
        // An animation that has been released can leave its address to the
        // next one, so identity alone isn't enough.
        if let store = stores[key], store.source === source {
            return store
        }
        let store = AnimatedImageFrameStore(key: key, source: source, pool: self, transform: transform, decoder: decoder)
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
