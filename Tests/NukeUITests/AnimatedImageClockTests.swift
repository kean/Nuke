// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import NukeUI

#if os(iOS) || os(tvOS) || os(visionOS)

import QuartzCore

/// What the clocks leave behind them: a display link outlives its clock until
/// something invalidates it, and the run loop is what holds it.
@Suite(.timeLimit(.minutes(1))) @MainActor
struct DisplayLinkClockTests {
    @Test func givesTheLinkBackWhenTheClockIsReleasedOffTheMainThread() async throws {
        let link = WeakBox()

        // A player nobody is watching sits on a paused clock, and a background
        // task can be the one to drop the last reference to it – which is the
        // one case the proxy can't answer, a paused link having no next tick.
        await Task.detached {
            var clock: DisplayLinkClock? = await MainActor.run { DisplayLinkClock { CADisplayLink(target: $0, selector: $1) } }
            await MainActor.run {
                clock?.isPaused = true
                link.value = clock?.link
            }
            #expect(link.value != nil)
            clock = nil // Released here, off the main thread
        }.value

        // The link is handed to the main queue, and invalidating it there is
        // what takes it out of the run loop that was holding it.
        for _ in 0..<100 where link.value != nil {
            await Task.yield()
        }
        #expect(link.value == nil)
    }
}

/// Holds a weak reference for a test that watches an object go, across the
/// threads the object is released on.
private final class WeakBox: @unchecked Sendable {
    weak var value: AnyObject?
}

#endif

#if os(macOS)

import AppKit

/// Which clock a player gets on AppKit, where a display link is asked of the
/// view being drawn into rather than made out of nothing.
@Suite(.timeLimit(.minutes(1))) @MainActor
struct AppKitClockTests {
    @Test func aViewGetsADisplayLinkOfItsOwn() {
        guard #available(macOS 14.0, *) else { return }

        #expect(makeAnimatedImageClock(for: NSView()) is DisplayLinkClock)
    }

    @Test func aPlayerWithNoViewRunsOnATimer() {
        // There is nothing to ask for a link, so the animation runs on a timer
        // at the rate it asks for.
        #expect(makeAnimatedImageClock() is TimerClock)
    }
}

#endif
