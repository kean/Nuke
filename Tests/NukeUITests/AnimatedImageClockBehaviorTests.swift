// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

#if canImport(UIKit)
import UIKit
#endif

#if os(macOS)
import AppKit
#endif

/// The clock a player runs on where there is no display link to be had:
/// watchOS, macOS before 14, and a player on AppKit with no view to ask for
/// one.
///
/// The tests that need it to tick wait for ticks rather than for time, and the
/// ones that need it not to tick wait for a second clock on the same run loop:
/// a timer still scheduled would have fired alongside it.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct TimerClockTests {
    // MARK: Rate

    @Test func startsPausedWithNoPreference() {
        let clock = TimerClock()

        #expect(clock.isPaused)
        #expect(clock.preferredFrameRate == 0)
        #expect(clock.period == 1.0 / 60)
    }

    @Test func runsAtTheRateItIsAskedFor() {
        let clock = TimerClock()

        clock.preferredFrameRate = 20

        #expect(clock.period == 1.0 / 20)
    }

    @Test func neverRunsFasterThanSixtyTicksASecond() {
        // The player drops the hint above 60 itself; a clock asked for more
        // anyway is capped rather than woken up 120 times a second.
        let clock = TimerClock()

        clock.preferredFrameRate = 120

        #expect(clock.period == 1.0 / 60)
    }

    @Test(arguments: [0.5, 0, -10, Double.nan])
    func treatsARateBelowOneTickASecondAsNoPreference(_ rate: Double) {
        // "0 for the fastest rate the platform offers" – and anything else that
        // isn't a usable rate means the same, rather than a timer that fires
        // once a minute or never.
        let clock = TimerClock()

        clock.preferredFrameRate = rate

        #expect(clock.period == 1.0 / 60)
        #expect(clock.isPaused)
    }

    // MARK: Ticking

    @Test func ticksOnceItIsUnpaused() async {
        let clock = TimerClock()

        let start = monotonicTime()
        clock.isPaused = false
        let deltas = await ticks(3, of: clock)
        let elapsed = monotonicTime() - start

        // Each tick reports the time since the one before it – the first one,
        // the time since the clock started – so between them they account
        // for no more than the time that actually passed.
        #expect(deltas.allSatisfy { $0 > 0 })
        #expect(deltas.reduce(0, +) <= elapsed)
        clock.isPaused = true
    }

    @Test func ticksNoMoreOftenThanItWasAskedTo() async {
        // A timer never fires before its fire date, so three ticks at 10 Hz
        // cover at least three tenths of a second however loaded the machine.
        let clock = TimerClock()
        clock.preferredFrameRate = 10

        clock.isPaused = false
        let deltas = await ticks(3, of: clock)

        #expect(deltas.reduce(0, +) >= 0.3 - 0.001)
        clock.isPaused = true
    }

    @Test func aNewRateTakesEffectWhileRunning() async {
        // GIVEN a clock running at 60 Hz
        let clock = TimerClock()
        clock.isPaused = false
        _ = await ticks(1, of: clock)

        // WHEN it is asked for 10 Hz – what a player does when the system
        // starts throttling in the middle of an animation
        clock.preferredFrameRate = 10
        let deltas = await ticks(3, of: clock)

        // THEN the timer is rescheduled: a 60 Hz timer left running would have
        // delivered these in a twentieth of a second
        #expect(clock.period == 0.1)
        #expect(deltas.reduce(0, +) >= 0.3 - 0.001)
        clock.isPaused = true
    }

    @Test func doesNotTickWhilePaused() async {
        // GIVEN a clock that has been running
        let clock = TimerClock()
        clock.isPaused = false
        _ = await ticks(1, of: clock)

        // WHEN it is paused
        clock.isPaused = true
        var count = 0
        clock.onTick = { _ in count += 1 }
        await elapseAFewTicks()

        // THEN its timer is gone
        #expect(count == 0)
    }

    @Test func aNewRateDoesNotStartAPausedClock() async {
        let clock = TimerClock()
        var count = 0
        clock.onTick = { _ in count += 1 }

        clock.preferredFrameRate = 30
        await elapseAFewTicks()

        #expect(clock.isPaused)
        #expect(count == 0)

        // ...and it is the rate the clock starts at once it is unpaused.
        #expect(clock.period == 1.0 / 30)
    }

    @Test func doesNotCountTheTimeItSpentPaused() async {
        // GIVEN a clock that ran, and was then paused for a while
        let clock = TimerClock()
        clock.isPaused = false
        _ = await ticks(1, of: clock)
        clock.isPaused = true
        await elapseAFewTicks()

        // WHEN it is resumed
        let resumed = monotonicTime()
        clock.isPaused = false
        let delta = await ticks(1, of: clock)[0]
        let sinceResumed = monotonicTime() - resumed

        // THEN the first tick reports the time since it was resumed and not
        // the pause: a player picks up where it was paused rather than
        // skipping ahead by however long it was paused for
        #expect(delta <= sinceResumed)
        clock.isPaused = true
    }

    // MARK: Lifetime

    @Test func aRunningClockIsNotKeptAliveByItsTimer() async {
        // The run loop holds a scheduled timer, and a timer holding its clock
        // would keep every player that ever animated alive.
        weak var weakClock: TimerClock?
        var count = 0
        do {
            let clock = TimerClock()
            clock.onTick = { _ in count += 1 }
            clock.isPaused = false
            weakClock = clock
        }

        #expect(weakClock == nil)

        await elapseAFewTicks()
        #expect(count == 0)
    }

    @Test func aRunningClockReleasedOffTheMainThreadGoesAway() async {
        let box = TimerClockWeakBox()

        // A player can be released from anywhere, and its clock with it. A
        // timer can only be invalidated on the thread it was scheduled on, so
        // this one is left to find its clock gone on its next fire and stop
        // itself.
        await Task.detached {
            var clock: TimerClock? = await MainActor.run {
                let clock = TimerClock()
                clock.isPaused = false
                box.value = clock
                return clock
            }
            #expect(clock != nil)
            clock = nil // Released here, off the main thread
        }.value

        #expect(box.value == nil)

        // Its timer is still scheduled, and fires into a clock that has gone.
        await elapseAFewTicks()
    }
}

#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)

import QuartzCore

/// The clock synchronized with the display: what every player on UIKit gets,
/// and what an ``AnimatedImageView`` gets on AppKit.
///
/// On AppKit a link is asked of a view, and a view in no window never ticks, so
/// the tests that need ticks run where a link is made out of nothing.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct DisplayLinkClockBehaviorTests {
    // MARK: State

    @Test func startsPausedAtASixtyHertzGuess() {
        guard #available(macOS 14.0, *) else { return }
        let clock = makeClock()

        #expect(clock.isPaused)
        #expect(clock.link.isPaused)
        #expect(clock.period == 1.0 / 60)
        #expect(clock.preferredFrameRate == 0)
    }

    @Test func pausingPausesTheLink() {
        guard #available(macOS 14.0, *) else { return }
        let clock = makeClock()

        clock.isPaused = false
        #expect(clock.link.isPaused == false)
        #expect(clock.isPaused == false)

        clock.isPaused = true
        #expect(clock.link.isPaused)
    }

    // MARK: Frame Rate

    @Test func asksTheLinkForTheRateAndAnythingUpToTheDisplays() {
        guard #available(macOS 14.0, *) else { return }
        let clock = makeClock()

        clock.preferredFrameRate = 20

        // Never below the rate the animation needs, and free to go as fast as
        // the display does.
        let range = clock.link.preferredFrameRateRange
        #expect(range.preferred == 20)
        #expect(range.minimum == 20)
        #expect(range.maximum == 120)
    }

    @Test func asksForTheWholeRangeAtTheTopOfIt() {
        guard #available(macOS 14.0, *) else { return }
        let clock = makeClock()

        clock.preferredFrameRate = 120

        let range = clock.link.preferredFrameRateRange
        #expect(range.minimum == 120)
        #expect(range.maximum == 120)
        #expect(range.preferred == 120)
    }

    @Test func goesBackToTheDefaultRangeWhenThePreferenceIsDropped() {
        // What a player does when the system stops throttling an animation
        // faster than the display: from 30 Hz back to "no preference".
        guard #available(macOS 14.0, *) else { return }
        let clock = makeClock()
        clock.preferredFrameRate = 30
        #expect(clock.link.preferredFrameRateRange.preferred == 30)

        clock.preferredFrameRate = 0

        #expect(isDefault(clock.link.preferredFrameRateRange))
    }

    @Test(arguments: [0.5, 240, -1])
    func usesTheDefaultRangeForARateNoDisplayOffers(_ rate: Double) {
        guard #available(macOS 14.0, *) else { return }
        let clock = makeClock()
        clock.preferredFrameRate = 20

        clock.preferredFrameRate = rate

        #expect(isDefault(clock.link.preferredFrameRateRange))
    }

    // MARK: Lifetime

    @Test func aRunningClockIsNotKeptAliveByItsLink() {
        // The run loop holds a running link, and the link holds its target: a
        // clock that was the target would never go away.
        guard #available(macOS 14.0, *) else { return }
        weak var weakClock: DisplayLinkClock?
        do {
            let clock = makeClock()
            clock.isPaused = false
            weakClock = clock
        }

        #expect(weakClock == nil)
    }

    @Test func givesTheLinkBackWhenReleasedOnTheMainThread() async {
        // A paused link – what a player nobody is watching sits on – has no
        // next tick for its proxy to notice the clock has gone, so it is the
        // clock that invalidates it, which is what takes it out of the run
        // loop holding it. UIKit hands the link out autoreleased, so it goes
        // on the next turn of the main queue rather than on the spot.
        guard #available(macOS 14.0, *) else { return }
        weak var weakLink: CADisplayLink?
        do {
            let clock = makeClock()
            weakLink = clock.link
            #expect(weakLink != nil)
            #expect(clock.isPaused)
        }

        for _ in 0..<100 where weakLink != nil {
            await Task.yield()
        }
        #expect(weakLink == nil)
    }

#if os(macOS)
    @Test func aLinkAskedOfAViewDoesNotKeepTheViewAlive() async {
        // The view owns the player, the player the clock, and the clock the
        // link: a link that held on to the view it was asked of would keep
        // every `AnimatedImageView` that ever played alive.
        guard #available(macOS 14.0, *) else { return }
        weak var weakView: NSView?
        var clock: (any AnimatedImageClock)?
        do {
            let view = NSView()
            weakView = view
            clock = makeAnimatedImageClock(for: view)
        }
        #expect(clock is DisplayLinkClock)
        clock?.isPaused = false

        for _ in 0..<100 where weakView != nil {
            await Task.yield()
        }
        #expect(weakView == nil)
        #expect(clock != nil)
    }

    @Test func givesTheLinkBackWhenReleasedOffTheMainThread() async {
        // The AppKit counterpart of `DisplayLinkClockTests`: a paused link has
        // no next tick to notice its clock has gone, so the clock hands it to
        // the main queue on its way out.
        guard #available(macOS 14.0, *) else { return }
        let link = DisplayLinkWeakBox()

        await Task.detached {
            var clock: DisplayLinkClock? = await MainActor.run {
                let clock = makeClock()
                link.value = clock.link
                return clock
            }
            #expect(clock != nil)
            #expect(link.value != nil)
            clock = nil // Released here, off the main thread
        }.value

        for _ in 0..<100 where link.value != nil {
            await Task.yield()
        }
        #expect(link.value == nil)
    }
#endif

    // MARK: Ticking

#if os(iOS) || os(tvOS) || os(visionOS)
    @Test func reportsTheRefreshIntervalOfTheDisplay() async {
        let clock = makeClock()

        clock.isPaused = false
        let first = await nextTick(of: clock)

        // The first tick has no tick before it to measure from and reports the
        // interval to the next refresh, which is also what the clock learns
        // its period from.
        #expect(first.delta == first.period)
        #expect(first.period > 0)
        #expect(first.period <= 1.0 / 10)

        // The ones after it measure the time between two refreshes.
        let deltas = await ticks(2, of: clock)
        clock.isPaused = true
        #expect(deltas.allSatisfy { $0 > 0 })
    }

    @Test func doesNotCountTheTimeItSpentPaused() async {
        // GIVEN a clock that ran, and was then paused for longer than a frame
        let clock = makeClock()
        clock.isPaused = false
        _ = await ticks(2, of: clock)
        clock.isPaused = true
        await elapseAFewTicks()

        // WHEN it is resumed
        clock.isPaused = false
        let tick = await nextTick(of: clock)
        clock.isPaused = true

        // THEN the first tick is worth one refresh, not the pause
        #expect(tick.delta == tick.period)
    }

    @Test func aPlayerOnUIKitGetsADisplayLink() {
        #expect(makeAnimatedImageClock() is DisplayLinkClock)
        // The view makes no difference where a link is made out of nothing.
        #expect(makeAnimatedImageClock(for: UIView()) is DisplayLinkClock)
    }

    /// Waits for the next tick, and returns what it reported along with the
    /// period the clock learned from it.
    private func nextTick(of clock: DisplayLinkClock) async -> (delta: TimeInterval, period: TimeInterval) {
        await withCheckedContinuation { continuation in
            clock.onTick = { [unowned clock] delta in
                clock.onTick = nil
                continuation.resume(returning: (delta, clock.period))
            }
        }
    }
#endif
}

/// A clock with a link of its own: made out of nothing on UIKit, and asked of a
/// view on AppKit, the way ``AnimatedImageView`` gets one.
@available(macOS 14.0, *)
@MainActor
private func makeClock() -> DisplayLinkClock {
#if os(macOS)
    let view = NSView()
    return DisplayLinkClock { view.displayLink(target: $0, selector: $1) }
#else
    return DisplayLinkClock { CADisplayLink(target: $0, selector: $1) }
#endif
}

/// `true` for the range a link has until it is asked for anything: the display
/// decides.
@available(macOS 14.0, *)
private func isDefault(_ range: CAFrameRateRange) -> Bool {
    let other = CAFrameRateRange.default
    return range.minimum == other.minimum && range.maximum == other.maximum && range.preferred == other.preferred
}

/// Holds a weak reference to a link across the threads its clock is released
/// on.
@available(macOS 14.0, *)
private final class DisplayLinkWeakBox: @unchecked Sendable {
    weak var value: CADisplayLink?
}

#endif

// MARK: - Helpers

/// Waits for the clock to tick the given number of times, and returns what
/// each tick reported.
@MainActor
private func ticks(_ count: Int, of clock: any AnimatedImageClock) async -> [TimeInterval] {
    await withCheckedContinuation { continuation in
        var deltas: [TimeInterval] = []
        clock.onTick = { delta in
            deltas.append(delta)
            guard deltas.count == count else { return }
            clock.onTick = nil
            continuation.resume(returning: deltas)
        }
    }
}

/// Lets a few refreshes' worth of time go by on the main run loop, measured by
/// a clock of its own: a timer on the same run loop at the same rate as the
/// one under test would have fired in that time.
@MainActor
private func elapseAFewTicks() async {
    let witness = TimerClock()
    witness.isPaused = false
    _ = await ticks(5, of: witness)
    witness.isPaused = true
}

/// Holds a weak reference to a clock across the threads it is released on.
private final class TimerClockWeakBox: @unchecked Sendable {
    weak var value: TimerClock?
}
