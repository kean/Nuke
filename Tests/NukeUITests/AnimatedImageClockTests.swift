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
        let link = WeakRef<CADisplayLink>()

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
        await waitUntil { link.value == nil }
        #expect(link.value == nil)
    }
}

#endif

#if os(macOS)

import AppKit

/// Which clock a player gets on AppKit, where a display link is asked of the
/// view being drawn into rather than made out of nothing.
@Suite(.timeLimit(.minutes(1))) @MainActor
struct AppKitClockTests {
    @Test func aViewGetsADisplayLinkOfItsOwn() {
        #expect(makeAnimatedImageClock(for: NSView()) is DisplayLinkClock)
    }

    @Test func aPlayerWithNoViewRunsOnATimer() {
        // There is nothing to ask for a link, so the animation runs on a timer
        // at the rate it asks for.
        #expect(makeAnimatedImageClock() is TimerClock)
    }
}

#endif
