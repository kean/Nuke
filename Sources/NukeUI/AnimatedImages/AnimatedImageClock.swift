// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import QuartzCore

/// The current value of a monotonic clock, in seconds.
///
/// `CACurrentMediaTime()` isn't available on watchOS; this reads the same
/// clock through a type that is.
func monotonicTime() -> TimeInterval {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
}

#if canImport(UIKit)
import UIKit
#endif

/// The heartbeat of ``AnimatedImagePlayer``.
///
/// The player advances only when something calls ``onTick``, which is what
/// makes playback testable: a test drives the animation frame by frame.
@MainActor
protocol AnimatedImageClock: AnyObject {
    /// Called with the number of seconds that passed since the previous tick.
    var onTick: ((TimeInterval) -> Void)? { get set }

    /// Whether the clock is currently ticking.
    var isPaused: Bool { get set }

    /// The rate the clock should aim for, in ticks per second, or `0` for the
    /// fastest rate the platform offers.
    ///
    /// A 10 fps animation doesn't need to be woken up 120 times a second, and
    /// on a display with a variable refresh rate saying so is a power win.
    var preferredFrameRate: Double { get set }
}

/// Returns the clock the players use unless a test replaces it.
@MainActor
func makeAnimatedImageClock() -> any AnimatedImageClock {
    AnimatedImageClockDriver.shared.makeClock()
}

/// Returns the one clock the driver is driven by.
@MainActor
func makePlatformAnimatedImageClock() -> any AnimatedImageClock {
#if os(iOS) || os(tvOS) || os(visionOS)
    DisplayLinkClock()
#else
    TimerClock()
#endif
}

/// The one heartbeat every animation on screen is driven by.
///
/// A display link is a run-loop source, a retained target, and a frame-rate
/// range the system reconciles with every other link in the app, so there is
/// one for the process and the players take subscriptions to it. It runs while
/// any subscription is running and asks for the rate of the fastest of them.
@MainActor
final class AnimatedImageClockDriver {
    /// The driver every player subscribes to.
    static let shared = AnimatedImageClockDriver()

    private let source: any AnimatedImageClock
    private var subscriptions: [Subscription] = []

    private struct Subscription {
        weak var clock: SharedAnimatedImageClock?
    }

    /// - parameter source: The clock to drive the subscriptions from. The tests
    /// pass one of their own; everything else takes the platform's.
    init(source: any AnimatedImageClock = makePlatformAnimatedImageClock()) {
        self.source = source
        source.onTick = { [weak self] in self?.tick($0) }
    }

    /// Returns a clock of a player's own, driven by this one.
    func makeClock() -> SharedAnimatedImageClock {
        let clock = SharedAnimatedImageClock(driver: self)
        subscriptions.append(Subscription(clock: clock))
        return clock
    }

    /// Works out whether the clock should be running, and how fast, from the
    /// subscriptions that are.
    func update() {
        subscriptions.removeAll { $0.clock == nil }
        let running = subscriptions.compactMap(\.clock).filter { !$0.isPaused }
        let rates = running.map(\.preferredFrameRate)
        // The fastest animation sets the rate. `0` means "whatever the display
        // does", so it beats any rate rather than losing to all of them.
        source.preferredFrameRate = rates.contains(0) ? 0 : (rates.max() ?? 0)
        source.isPaused = running.isEmpty
    }

    /// The number of clocks the driver is ticking, for the tests.
    var runningClockCount: Int {
        subscriptions.compactMap(\.clock).count { !$0.isPaused }
    }

    private func tick(_ delta: TimeInterval) {
        var hasReleasedClocks = false
        for subscription in subscriptions {
            guard let clock = subscription.clock else {
                hasReleasedClocks = true
                continue
            }
            guard !clock.isPaused else { continue }
            clock.onTick?(delta)
        }
        // A player released while playing leaves the driver running for
        // nobody until something notices, and a tick is the first thing to.
        if hasReleasedClocks {
            update()
        }
    }
}

/// One player's share of ``AnimatedImageClockDriver``: whether it is running
/// and how fast it would like to, over a clock the whole app shares.
@MainActor
final class SharedAnimatedImageClock: AnimatedImageClock {
    var onTick: ((TimeInterval) -> Void)?

    var isPaused = true {
        didSet {
            guard isPaused != oldValue else { return }
            driver?.update()
        }
    }

    var preferredFrameRate: Double = 0 {
        didSet {
            guard preferredFrameRate != oldValue, !isPaused else { return }
            driver?.update()
        }
    }

    private weak var driver: AnimatedImageClockDriver?

    init(driver: AnimatedImageClockDriver) {
        self.driver = driver
    }

    // No `deinit`: the driver holds its subscriptions weakly and drops this one
    // on its next tick, which a `deinit` off the main actor could not do anyway.
}

#if os(iOS) || os(tvOS) || os(visionOS)

/// A clock driven by `CADisplayLink`, synchronized with the display refresh.
@MainActor
final class DisplayLinkClock: AnimatedImageClock {
    var onTick: ((TimeInterval) -> Void)?

    var isPaused: Bool {
        get { link.isPaused }
        set {
            guard link.isPaused != newValue else { return }
            // The gap while the clock was paused is not time the animation
            // lived through.
            lastTimestamp = 0
            link.isPaused = newValue
        }
    }

    var preferredFrameRate: Double = 0 {
        didSet {
            guard preferredFrameRate != oldValue else { return }
            updatePreferredFrameRateRange()
        }
    }

    private var link: CADisplayLink!
    private var lastTimestamp: CFTimeInterval = 0

    init() {
        // A display link retains its target until it is invalidated, so the
        // target is a proxy rather than the clock itself.
        let proxy = DisplayLinkProxy()
        link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.onDisplayLink(_:)))
        proxy.clock = self
        link.isPaused = true
        link.add(to: .main, forMode: .common)
    }

    deinit {
        // A display link must be invalidated on the thread it was added to. A
        // clock released anywhere else leaves the link to the proxy, which
        // stops it on its next tick.
        if Thread.isMainThread {
            MainActor.assumeIsolated { link.invalidate() }
        }
    }

    fileprivate func handle(_ link: CADisplayLink) {
        // `timestamp` is when the previous frame was displayed, so consecutive
        // values measure the time that actually passed, hitches included.
        let delta: TimeInterval
        if lastTimestamp > 0 {
            delta = link.timestamp - lastTimestamp
        } else {
            delta = link.targetTimestamp - link.timestamp
        }
        lastTimestamp = link.timestamp
        guard delta > 0 else { return }
        onTick?(delta)
    }

    private func updatePreferredFrameRateRange() {
        guard preferredFrameRate >= 1, preferredFrameRate <= 120 else {
            link.preferredFrameRateRange = .default
            return
        }
        let preferred = Float(preferredFrameRate)
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: preferred,
            maximum: max(preferred, 120),
            preferred: preferred
        )
    }
}

/// Breaks the retain cycle between the display link and the clock: the run
/// loop retains the link, and the link retains its target until invalidated.
@MainActor
private final class DisplayLinkProxy {
    weak var clock: DisplayLinkClock?

    @objc func onDisplayLink(_ link: CADisplayLink) {
        guard let clock else {
            return link.invalidate() // The clock is gone: stop the run loop source
        }
        clock.handle(link)
    }
}

#endif

/// A clock driven by a timer, for the platforms without `CADisplayLink`:
/// macOS and watchOS.
///
/// It is scheduled at the rate the animation asks for rather than at the
/// refresh rate, so it wakes up less often than a display link would.
@MainActor
final class TimerClock: AnimatedImageClock {
    var onTick: ((TimeInterval) -> Void)?

    var isPaused: Bool = true {
        didSet {
            guard isPaused != oldValue else { return }
            if isPaused {
                stop()
            } else {
                start()
            }
        }
    }

    var preferredFrameRate: Double = 0 {
        didSet {
            guard preferredFrameRate != oldValue, !isPaused else { return }
            stop()
            start()
        }
    }

    private var timer: Timer?
    private var lastTime: CFTimeInterval = 0

    init() {}

    deinit {
        // See `DisplayLinkClock.deinit`. A timer released off the main thread
        // is stopped by its own block on the next fire.
        if Thread.isMainThread {
            MainActor.assumeIsolated { timer?.invalidate() }
        }
    }

    private func start() {
        let rate = preferredFrameRate >= 1 ? min(preferredFrameRate, 60) : 60
        lastTime = monotonicTime()
        let timer = Timer(timeInterval: 1 / rate, repeats: true) { [weak self] timer in
            guard let self else {
                return timer.invalidate() // The clock is gone
            }
            MainActor.assumeIsolated { self.tick() }
        }
        // `.common` keeps the animation running while a scroll view is tracked.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        lastTime = 0
    }

    private func tick() {
        let now = monotonicTime()
        let delta = lastTime > 0 ? now - lastTime : 0
        lastTime = now
        guard delta > 0 else { return }
        onTick?(delta)
    }
}
