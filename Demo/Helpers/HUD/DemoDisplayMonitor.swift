// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import QuartzCore

/// Whether the main thread keeps up with the display: the frames per second,
/// the refreshes it missed, and the longest wait between two frames.
///
/// Make one per thing that counts and reset it when it suits: a screen that
/// counts the hitches of one scroll doesn't start the HUD's figures over. It
/// watches between ``start()`` and ``stop()`` and nowhere else, because its
/// display link isn't free. The first link in a process costs a run loop
/// wakeup on every refresh, about a hundred microseconds, and holds a display
/// with a variable refresh rate at its highest. A second link costs next to
/// nothing: the system calls them all in one pass.
///
/// ```swift
/// let monitor = DemoDisplayMonitor()
/// monitor.start()
/// // … scroll …
/// print(monitor.figures.droppedFrameCount, monitor.figures.longestFrame)
/// monitor.stop()
/// ```
///
/// The link is called on the main thread, so the figures are the frames a busy
/// main thread cost. A frame the render server drops on its own isn't seen.
/// `CADisplayLink` is the one part of the HUD's measuring that is particular
/// to iOS; a Mac would take its link from the screen.
@MainActor
final class DemoDisplayMonitor {
    /// What the monitor saw since it was created or reset, while it watched.
    struct Figures: Sendable, Equatable {
        /// The frames over the last whole second watched, or `nil` until a
        /// second has been.
        var framesPerSecond: Double?
        /// The time between two refreshes at the rate the link is driven at:
        /// what a frame that arrives on time takes.
        var refreshInterval: TimeInterval?
        /// The refreshes the main thread missed: for every frame that arrived
        /// late, the refresh intervals it was late by.
        var droppedFrameCount = 0
        /// The frames that arrived late, however many refreshes each one cost.
        var hitchCount = 0
        /// How late the late frames were, added up.
        var hitchDuration: TimeInterval = 0
        /// The longest time between two frames.
        var longestFrame: TimeInterval = 0
        /// How long the monitor watched.
        var watchedDuration: TimeInterval = 0

        /// Seconds of hitches per second watched – Apple's hitch time ratio,
        /// usually written in milliseconds per second – or `nil` before
        /// anything was watched.
        var hitchTimeRatio: Double? {
            watchedDuration > 0 ? hitchDuration / watchedDuration : nil
        }
    }

    /// A frame that arrived a refresh or more late.
    struct Hitch: Sendable, Equatable {
        /// When the late frame arrived, in the time base of
        /// `CACurrentMediaTime()`.
        var timestamp: CFTimeInterval
        /// The time since the frame before it.
        var duration: TimeInterval
        /// The interval the link was driven at: what the frame should have
        /// taken.
        var refreshInterval: TimeInterval
        /// The refreshes it missed.
        var missedRefreshCount: Int

        /// How long the main thread held the frame up: its duration less the
        /// refresh it was due in. A 200 ms stall at 60 Hz is a 217 ms frame,
        /// and a 200 ms stall.
        var stall: TimeInterval {
            duration - refreshInterval
        }
    }

    /// The figures now. Read it as often as you like: it is a copy.
    private(set) var figures = Figures()

    /// Called with every late frame as it arrives, on the main thread, for a
    /// screen that lists them rather than counts them. The figures include
    /// the frame by then.
    var onHitch: (@MainActor (Hitch) -> Void)?

    /// Whether the monitor is watching.
    var isWatching: Bool { link != nil }

    private var link: CADisplayLink?
    /// The previous frame, or `nil` when the next one is the first one watched.
    private var previousFrame: (timestamp: CFTimeInterval, targetTimestamp: CFTimeInterval)?
    private var windowStart: CFTimeInterval = 0
    private var windowFrameCount = 0

    init() {}

    /// Starts watching the display. Does nothing if it is watching already.
    func start() {
        guard link == nil else { return }
        // The proxy keeps the run loop from retaining the monitor through the
        // link, which retains its target until it is invalidated.
        let proxy = DisplayLinkProxy()
        proxy.monitor = self
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.onDisplayLink(_:)))
        // `.common`, or a scroll view being tracked would stop the count.
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Stops watching. The figures stay as they are.
    func stop() {
        link?.invalidate()
        link = nil
        // The time until the display is watched again isn't a frame.
        previousFrame = nil
        figures.framesPerSecond = nil
    }

    /// Starts the counts over. A monitor that is watching goes on watching,
    /// and the frame rate, which is only ever the last second's, stays.
    func reset() {
        figures = Figures(framesPerSecond: figures.framesPerSecond, refreshInterval: figures.refreshInterval)
    }

    fileprivate func handle(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        let targetTimestamp = link.targetTimestamp
        if targetTimestamp > timestamp {
            figures.refreshInterval = targetTimestamp - timestamp
        }
        guard let previous = previousFrame else {
            previousFrame = (timestamp, targetTimestamp)
            windowStart = timestamp
            windowFrameCount = 0
            return
        }
        previousFrame = (timestamp, targetTimestamp)

        let elapsed = timestamp - previous.timestamp
        figures.watchedDuration += elapsed
        figures.longestFrame = max(figures.longestFrame, elapsed)
        // Measured against the interval the link is driven at, not the
        // display's highest rate: a link the system holds at 60 Hz on a 120 Hz
        // display isn't dropping every other frame.
        let interval = previous.targetTimestamp - previous.timestamp
        if interval > 0 {
            let late = timestamp - previous.targetTimestamp
            // Rounded, so the jitter of a frame that is on time isn't a drop.
            let missed = Int((late / interval).rounded())
            if missed > 0 {
                figures.droppedFrameCount += missed
                figures.hitchCount += 1
                figures.hitchDuration += late
                onHitch?(Hitch(timestamp: timestamp, duration: elapsed, refreshInterval: interval, missedRefreshCount: missed))
            }
        }

        windowFrameCount += 1
        let window = timestamp - windowStart
        if window >= 1 {
            figures.framesPerSecond = Double(windowFrameCount) / window
            windowStart = timestamp
            windowFrameCount = 0
        }
    }
}

/// Stands between the display link and the monitor, which the link would
/// otherwise retain for as long as it runs. A monitor that is gone
/// invalidates the link on its next call.
@MainActor
private final class DisplayLinkProxy {
    weak var monitor: DemoDisplayMonitor?

    @objc func onDisplayLink(_ link: CADisplayLink) {
        guard let monitor else {
            return link.invalidate()
        }
        monitor.handle(link)
    }
}
