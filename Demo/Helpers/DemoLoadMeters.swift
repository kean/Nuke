// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import QuartzCore
import SwiftUI
import UIKit
import os

/// How smoothly the app is drawing, measured the way an app measures it: with
/// a display link of its own.
///
/// ``AnimatedImagePlayer/Diagnostics`` says what the players are doing. This
/// says what it is costing the screen they are on, which is the number that
/// decides whether a wall of animations is worth having. A decoder that keeps
/// up perfectly and a scroll view that stutters is still a bad screen.
@MainActor
final class DemoScreenFrameMeter: NSObject {
    /// The number of frames the display drew per second, over the last second.
    private(set) var framesPerSecond: Double = 0

    /// The number of frames that arrived later than the display link said they
    /// would, since the last ``reset()``.
    private(set) var lateFrameCount = 0

    /// The longest a frame ran over its deadline, in seconds.
    private(set) var worstFrameDelay: TimeInterval = 0

    /// What the display is capable of, which is what ``framesPerSecond`` is
    /// worth reading against.
    let displayFrameRate = Double(UIScreen.main.maximumFramesPerSecond)

    private var link: CADisplayLink?
    private var expectedTimestamp: CFTimeInterval?
    private var windowStart: CFTimeInterval = 0
    private var windowFrameCount = 0

    /// A frame this much past its deadline is a late one. Below one refresh
    /// at any rate the displays run at, and above the jitter in the timestamps.
    private static let tolerance: TimeInterval = 0.003

    func start() {
        guard link == nil else { return }
        reset()
        let link = CADisplayLink(target: self, selector: #selector(step))
        // The common mode, so that the figure keeps being measured while a
        // list is being scrolled – which is when it matters.
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    func reset() {
        framesPerSecond = 0
        lateFrameCount = 0
        worstFrameDelay = 0
        expectedTimestamp = nil
        windowStart = 0
        windowFrameCount = 0
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        if let expected = expectedTimestamp, now > expected + Self.tolerance {
            lateFrameCount += 1
            worstFrameDelay = max(worstFrameDelay, now - expected)
        }
        // The link's own idea of when the next frame is due, rather than the
        // display's maximum: a 120 Hz screen with nothing to draw runs at 60,
        // and counting every frame of that as a dropped one would be a lie.
        expectedTimestamp = link.targetTimestamp

        windowFrameCount += 1
        guard windowStart > 0 else {
            return windowStart = now
        }
        let elapsed = now - windowStart
        guard elapsed >= 1 else { return }
        framesPerSecond = Double(windowFrameCount) / elapsed
        windowFrameCount = 0
        windowStart = now
    }
}

/// The memory the app is using, the way the system counts it.
///
/// ``AnimatedImageFramePool/totalCost`` is the decoded frames it is holding.
/// This is everything: those frames, the ones the views are drawing, what the
/// decoders keep while they work, and the rest of the app. A screenful of
/// animations always costs more than the pool's ceiling, and the gap between
/// the two figures is how much more.
func demoMemoryFootprint() -> Int? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { info in
        info.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }
    return Int(info.phys_footprint)
}

/// How much more memory the app may use before the system stops it. `nil` in
/// the simulator, which doesn't have a limit to report.
func demoAvailableMemory() -> Int? {
    let available = os_proc_available_memory()
    return available > 0 ? available : nil
}

/// The rate a counter is rising at, per second.
///
/// The counters in the diagnostics are cumulative – frames decoded, frames
/// shown, frames missed – and it is the rate they are climbing at that says
/// what a screen is costing right now. Sampling ten times a second lands the
/// odd decode in one window and not the next, so the figure is smoothed rather
/// than reported raw.
struct DemoRate {
    private(set) var value: Double = 0

    private var total: Double?
    private var time: TimeInterval?

    /// The weight of a new sample. A tenth of a second apart, this settles in
    /// about a second, which is as fast as a number is worth reading.
    private static let smoothing = 0.2

    mutating func update(_ total: Double, at time: TimeInterval) {
        defer {
            self.total = total
            self.time = time
        }
        guard let last = self.total, let lastTime = self.time, time > lastTime else { return }
        // Counters that went backwards are a wall that was rebuilt under them.
        let rate = max(0, total - last) / (time - lastTime)
        value += (rate - value) * Self.smoothing
    }
}
