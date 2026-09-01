// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

/// The one clock every animation on screen is driven by.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageClockDriverTests {
    private let source = ManualClock()
    private let driver: AnimatedImageClockDriver

    init() {
        driver = AnimatedImageClockDriver(source: source)
    }

    @Test func staysStillWhileNothingIsPlaying() {
        _ = driver.makeClock()
        _ = driver.makeClock()

        #expect(source.isPaused)
    }

    @Test func runsWhileAnythingIsPlaying() {
        let first = driver.makeClock()
        let second = driver.makeClock()

        first.isPaused = false

        #expect(source.isPaused == false)

        second.isPaused = false
        first.isPaused = true

        #expect(source.isPaused == false) // The second one is still going

        second.isPaused = true

        #expect(source.isPaused)
    }

    @Test func oneTickDrivesEveryAnimation() {
        let first = driver.makeClock()
        let second = driver.makeClock()
        var ticks: [String: TimeInterval] = [:]
        first.onTick = { ticks["first"] = $0 }
        second.onTick = { ticks["second"] = $0 }
        first.isPaused = false
        second.isPaused = false

        source.tick(0.05)

        #expect(ticks == ["first": 0.05, "second": 0.05])
    }

    @Test func aPausedAnimationIsNotTicked() {
        let running = driver.makeClock()
        let paused = driver.makeClock()
        var runningTicks = 0
        var pausedTicks = 0
        running.onTick = { _ in runningTicks += 1 }
        paused.onTick = { _ in pausedTicks += 1 }
        running.isPaused = false

        source.tick(0.05)

        #expect(runningTicks == 1)
        #expect(pausedTicks == 0)
    }

    @Test func asksForTheRateOfTheFastestAnimation() {
        let slow = driver.makeClock()
        let fast = driver.makeClock()
        slow.preferredFrameRate = 20
        fast.preferredFrameRate = 50

        slow.isPaused = false
        #expect(source.preferredFrameRate == 20)

        fast.isPaused = false
        #expect(source.preferredFrameRate == 50)

        // The fast one stops and the rate drops back to what is left.
        fast.isPaused = true
        #expect(source.preferredFrameRate == 20)
    }

    @Test func anAnimationWithNoRateToAskForBeatsEveryRate() {
        // `0` is how an animation faster than the display says "as often as you
        // can", which is more than any number another one could name.
        let slow = driver.makeClock()
        let unbounded = driver.makeClock()
        slow.preferredFrameRate = 20
        unbounded.preferredFrameRate = 0

        slow.isPaused = false
        unbounded.isPaused = false

        #expect(source.preferredFrameRate == 0)
    }

    @Test func followsARateThatChangesWhileTheAnimationIsPlaying() {
        let clock = driver.makeClock()
        clock.preferredFrameRate = 20
        clock.isPaused = false
        #expect(source.preferredFrameRate == 20)

        clock.preferredFrameRate = 45

        #expect(source.preferredFrameRate == 45)
    }

    @Test func stopsWhenTheLastPlayerIsReleased() {
        var released: SharedAnimatedImageClock? = driver.makeClock()
        released?.isPaused = false
        #expect(source.isPaused == false)

        released = nil
        // A clock is dropped on the driver's next tick: a `deinit` isn't on the
        // main actor and can't reach back into it to say so.
        source.tick(0.05)

        #expect(source.isPaused)
        #expect(driver.runningClockCount == 0)
    }

    @Test func everyPlayerTakesAShareOfOneClock() {
        // What this is all for: twenty animations used to mean twenty display
        // links, all firing on the same vsync to do the same thing.
        let players = (0..<20).map { _ in driver.makeClock() }
        for player in players { player.isPaused = false }

        #expect(driver.runningClockCount == 20)
        #expect(source.isPaused == false)
    }
}
