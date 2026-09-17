// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import UIKit

/// Scrolls a scroll view from the top at a fixed speed for a fixed time,
/// turning at either end: the same scroll on every run, so that two runs –
/// of two image sources, or two pipeline configurations – compare by what
/// they cost rather than by how a finger moved.
///
/// A display link moves the view on every frame by as far as the time since
/// the last frame says, so the speed holds whatever the frame rate, and a
/// late frame jumps the way a real scroll does. Touches are off while it
/// runs: they would fight the scroll.
///
/// ```swift
/// autoScroll = DemoAutoScroll(scrollView: collectionView, speed: 3000, duration: 10) { elapsed in
///     // Stopped, or scrolled for `duration`.
/// }
/// ```
@MainActor
final class DemoAutoScroll {
    private weak var scrollView: UIScrollView?
    private let speed: CGFloat
    private let duration: TimeInterval
    private let completion: (TimeInterval) -> Void
    private var link: CADisplayLink?
    private var startTimestamp: CFTimeInterval?
    private var previousTimestamp: CFTimeInterval?
    private var direction: CGFloat = 1
    /// How long it has scrolled.
    private(set) var elapsed: TimeInterval = 0

    /// Starts scrolling at once.
    ///
    /// - parameters:
    ///   - speed: Points per second.
    ///   - duration: How long to scroll for, in seconds.
    ///   - completion: Called once, with the time it scrolled for, when the
    ///   time is up or ``stop()`` is called.
    init(scrollView: UIScrollView, speed: CGFloat, duration: TimeInterval, completion: @escaping (TimeInterval) -> Void) {
        self.scrollView = scrollView
        self.speed = speed
        self.duration = duration
        self.completion = completion

        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: false)
        scrollView.isScrollEnabled = false

        // The link retains its target until it is invalidated; the proxy
        // keeps it from retaining this.
        let proxy = Proxy()
        proxy.autoScroll = self
        let link = CADisplayLink(target: proxy, selector: #selector(Proxy.onDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    fileprivate func step(_ link: CADisplayLink) {
        guard let scrollView else {
            return stop()
        }
        let timestamp = link.timestamp
        guard let previous = previousTimestamp, let start = startTimestamp else {
            startTimestamp = timestamp
            previousTimestamp = timestamp
            return
        }
        previousTimestamp = timestamp
        elapsed = timestamp - start

        let top = -scrollView.adjustedContentInset.top
        let bottom = max(top, scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height)
        var y = scrollView.contentOffset.y + direction * speed * (timestamp - previous)
        if y >= bottom {
            y = bottom
            direction = -1
        } else if y <= top {
            y = top
            direction = 1
        }
        scrollView.contentOffset.y = y

        if elapsed >= duration {
            stop()
        }
    }

    /// Stops scrolling, gives the touches back, and calls the completion.
    /// Does nothing if it has stopped already.
    func stop() {
        guard let link else { return }
        link.invalidate()
        self.link = nil
        scrollView?.isScrollEnabled = true
        completion(elapsed)
    }

    @MainActor
    private final class Proxy {
        weak var autoScroll: DemoAutoScroll?

        @objc func onDisplayLink(_ link: CADisplayLink) {
            guard let autoScroll else {
                return link.invalidate()
            }
            autoScroll.step(link)
        }
    }
}
