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

    /// The time between two ticks at the rate the clock is running, in
    /// seconds: what a tick that arrives on time reports.
    var period: TimeInterval { get }
}

/// Returns a clock for a player.
///
/// Every player has one of its own. A display link costs the run loop one
/// wakeup per refresh whether there is one link or a hundred – the system
/// folds every link in the process into that wakeup, and each link past the
/// first adds a fraction of a microsecond to it – so a clock shared between
/// the players would save nothing worth its bookkeeping.
@MainActor
func makeAnimatedImageClock() -> any AnimatedImageClock {
#if os(iOS) || os(tvOS) || os(visionOS)
    DisplayLinkClock { CADisplayLink(target: $0, selector: $1) }
#else
    TimerClock()
#endif
}

#if !os(watchOS)

/// Returns a clock for a player drawing into the given view.
///
/// AppKit has no display link of its own: one is asked of the view being drawn
/// into, and follows that view between displays, ticking while it is in a
/// window that is on screen and not while it isn't. Everywhere else the view
/// makes no difference.
@MainActor
func makeAnimatedImageClock(for view: _PlatformBaseView) -> any AnimatedImageClock {
#if os(macOS)
    if #available(macOS 14.0, *) {
        return DisplayLinkClock { view.displayLink(target: $0, selector: $1) }
    }
    return TimerClock()
#else
    return makeAnimatedImageClock()
#endif
}

#endif

#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)

/// A clock driven by `CADisplayLink`, synchronized with the display refresh.
@available(macOS 14.0, *)
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

    /// The refresh interval the link last reported, and a 60 Hz guess until
    /// it has reported one.
    private(set) var period: TimeInterval = 1.0 / 60

    /// `nonisolated(unsafe)` so that `deinit` can reach it from whatever
    /// thread released the clock, which is the one thing outside the main
    /// actor that touches it. The tests watch it go.
    private(set) nonisolated(unsafe) var link: CADisplayLink!
    private var lastTimestamp: CFTimeInterval = 0

    /// - parameter makeLink: What produces the link, because AppKit asks the
    /// view being drawn into for one and UIKit makes it out of nothing.
    init(makeLink: (AnyObject, Selector) -> CADisplayLink) {
        // The proxy is what keeps the run loop from retaining the clock: a
        // display link retains its target until it is invalidated, and the
        // clock is owned by a player that has to be able to go away.
        let proxy = DisplayLinkProxy()
        link = makeLink(proxy, #selector(DisplayLinkProxy.onDisplayLink(_:)))
        proxy.clock = self
        link.isPaused = true
        link.add(to: .main, forMode: .common)
    }

    deinit {
        // A display link must be invalidated on the thread it was added to, so
        // a clock released anywhere but the main thread hands its link back to
        // the main queue. Leaving it to the proxy is not enough: the proxy
        // stops the link on its next tick, and a paused link – which is what a
        // player nobody is watching sits on – has no next tick, so the link and
        // its proxy would stay in the run loop for the life of the process.
        if Thread.isMainThread {
            MainActor.assumeIsolated { link.invalidate() }
        } else {
            DispatchQueue.main.async { [link] in link?.invalidate() }
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
        // The interval to the next frame is the display's current one, however
        // late this tick was.
        if link.targetTimestamp > link.timestamp {
            period = link.targetTimestamp - link.timestamp
        }
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

/// Breaks the retain cycle between the display link and the clock.
///
/// A display link retains its target until it is invalidated, and the run loop
/// retains the link, so a target that owns the clock would keep every player
/// that ever animated alive for the lifetime of the app.
@available(macOS 14.0, *)
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

/// A clock driven by a timer, for where there is no display link to be had:
/// watchOS, and macOS before 14 or a player with no view to ask for one.
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

    var period: TimeInterval { 1 / rate }

    private var timer: Timer?
    private var lastTime: CFTimeInterval = 0

    init() {}

    deinit {
        // A timer released off the main thread is stopped by its own block on
        // the next fire, and a paused clock has no timer to stop: unlike a
        // display link, a timer that isn't running isn't in the run loop
        // either.
        if Thread.isMainThread {
            MainActor.assumeIsolated { timer?.invalidate() }
        }
    }

    /// The rate the timer runs at: what the animation asked for, up to 60.
    private var rate: Double {
        preferredFrameRate >= 1 ? min(preferredFrameRate, 60) : 60
    }

    private func start() {
        lastTime = monotonicTime()
        let timer = Timer(timeInterval: period, repeats: true) { [weak self] timer in
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
