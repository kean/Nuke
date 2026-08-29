// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import QuartzCore

/// The current value of a monotonic clock, in seconds.
///
/// `CACurrentMediaTime()` would do everywhere except watchOS, where it isn't
/// available. This reads the same clock through a type that is.
func monotonicTime() -> TimeInterval {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
}

#if canImport(UIKit)
import UIKit
#endif

/// The heartbeat of ``AnimatedImagePlayer``.
///
/// The player never reads a clock of its own: it advances only when something
/// calls ``onTick``, which is what makes playback testable – a test drives the
/// animation frame by frame instead of sleeping and hoping.
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
    /// on a display that can vary its refresh rate, saying so out loud is a
    /// measurable power win.
    var preferredFrameRate: Double { get set }

    /// Stops the clock permanently. The clock is unusable afterwards.
    func invalidate()
}

/// Returns the clock the players use unless a test replaces it.
@MainActor
func makeAnimatedImageClock() -> any AnimatedImageClock {
#if os(iOS) || os(tvOS) || os(visionOS)
    DisplayLinkClock()
#else
    TimerClock()
#endif
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
            // Drop the stale timestamp: the gap while the clock was paused is
            // not time the animation lived through.
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
        // The proxy is what keeps the run loop from retaining the clock: a
        // display link retains its target until it is invalidated, and the
        // clock is owned by a player that has to be able to go away.
        let proxy = DisplayLinkProxy()
        link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.onDisplayLink(_:)))
        proxy.clock = self
        link.isPaused = true
        link.add(to: .main, forMode: .common)
    }

    deinit {
        // A display link must be invalidated on the thread it was added to, so
        // only the main thread can do it here. A clock released anywhere else
        // leaves the link to the proxy, which stops it on its next tick.
        if Thread.isMainThread {
            MainActor.assumeIsolated { link.invalidate() }
        }
    }

    func invalidate() {
        link.isPaused = true
        link.invalidate()
    }

    fileprivate func handle(_ link: CADisplayLink) {
        // `timestamp` is when the previous frame was displayed, so consecutive
        // values measure the time that actually passed, hitches included. The
        // player is what decides how much of a gap it is willing to swallow.
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

/// Breaks the retain cycle between the display link and the clock.
///
/// A display link retains its target until it is invalidated, and the run loop
/// retains the link, so a target that owns the clock would keep every player
/// that ever animated alive for the lifetime of the app.
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
/// It is not synchronized with the display, but it is scheduled at the rate the
/// animation asks for rather than at the refresh rate, so it wakes up less
/// often than a display link would.
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
    private var isInvalidated = false

    init() {}

    deinit {
        // See `DisplayLinkClock.deinit`. A timer released off the main thread
        // is stopped by its own block on the next fire.
        if Thread.isMainThread {
            MainActor.assumeIsolated { timer?.invalidate() }
        }
    }

    func invalidate() {
        isInvalidated = true
        stop()
    }

    private func start() {
        guard !isInvalidated else { return }
        let rate = preferredFrameRate >= 1 ? min(preferredFrameRate, 60) : 60
        lastTime = monotonicTime()
        let timer = Timer(timeInterval: 1 / rate, repeats: true) { [weak self] timer in
            guard let self else {
                return timer.invalidate() // The clock is gone
            }
            MainActor.assumeIsolated { self.tick() }
        }
        // `.common` keeps the animation running while a scroll view is being
        // tracked, which is the entire point of running one in a list.
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
