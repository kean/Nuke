// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

/// What tells the players that the system is asking for less work, and what
/// they do about it.
///
/// Nothing can put a device in Low Power Mode on a test's behalf, so most of
/// these drive a monitor that doesn't follow the system. The ones that do
/// follow it compare against whatever state the machine is in.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImagePowerMonitorTests {
    /// A pool of its own, so that nothing these players hold shows up in the
    /// suites that measure the shared one.
    private let pool = AnimatedImageFramePool()

    // MARK: A Monitor of Your Own

    @Test func startsInTheStateItIsGiven() {
        #expect(AnimatedImagePowerMonitor(isThrottling: true).isThrottling)
        #expect(AnimatedImagePowerMonitor(isThrottling: false).isThrottling == false)
    }

    @Test func tellsEveryPlayerWhenTheStateChanges() {
        // GIVEN two animations, one playing that asks for a 40 Hz clock, and
        // one paused and faster than the display that asks for none. A player
        // that isn't playing is the one to start at the wrong rate later if it
        // misses the change.
        let power = AnimatedImagePowerMonitor(isThrottling: false)
        let fast = makePlayer(delay: 0.05, power: power)
        let faster = makePlayer(delay: 0.02, power: power)
        fast.player.play()
        #expect(fast.clock.preferredFrameRate == 40)
        #expect(faster.clock.preferredFrameRate == 0)
        #expect(faster.player.isPlaying == false)

        // WHEN the system starts throttling
        power.setThrottling(true)

        // THEN both are held to 30
        #expect(power.isThrottling)
        #expect(fast.clock.preferredFrameRate == 30)
        #expect(faster.clock.preferredFrameRate == 30)
        withExtendedLifetime((fast.player, faster.player)) {}
    }

    @Test func leavesThePlayersAloneWhenNothingChanged() {
        // Both notifications the system posts arrive for either reason, so most
        // of them report the state the monitor is already in.
        let power = AnimatedImagePowerMonitor(isThrottling: true)
        let (player, clock) = makePlayer(delay: 0.05, power: power)
        clock.preferredFrameRate = -1 // What no player asks for

        power.setThrottling(true)

        #expect(clock.preferredFrameRate == -1)
        withExtendedLifetime(player) {}
    }

    @Test func doesNotKeepAPlayerAlive() {
        let power = AnimatedImagePowerMonitor(isThrottling: false)
        weak var weakPlayer: AnimatedImagePlayer?
        let survivor = makePlayer(delay: 0.05, power: power)
        do {
            let (player, _) = makePlayer(delay: 0.1, power: power)
            weakPlayer = player
        }

        #expect(weakPlayer == nil)

        // And the players that are left are still told.
        power.setThrottling(true)
        #expect(survivor.clock.preferredFrameRate == 30)
        withExtendedLifetime(survivor.player) {}
    }

    // MARK: Following the System

    @Test func startsInTheStateOfTheSystem() {
        let monitor = AnimatedImagePowerMonitor()

        #expect(monitor.isThrottling == Self.isSystemThrottling)
    }

    @Test(arguments: [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification])
    func readsTheSystemAgainWhenItPostsAChange(_ name: Notification.Name) async {
        // GIVEN a monitor out of step with the system, the way it is the
        // moment the system changes state
        let monitor = AnimatedImagePowerMonitor()
        let (player, clock) = makePlayer(delay: 0.05, power: monitor)
        let expected = Self.isSystemThrottling
        monitor.setThrottling(!expected)

        // WHEN the system says so. Every monitor that follows the system reads
        // it again, which for one already in step changes nothing.
        NotificationCenter.default.post(name: name, object: ProcessInfo.processInfo)
        for _ in 0..<100 where monitor.isThrottling != expected {
            await Task.yield()
        }

        // THEN it is back in step, and so are its players
        #expect(monitor.isThrottling == expected)
        #expect(clock.preferredFrameRate == (expected ? 30 : 40))
        withExtendedLifetime(player) {}
    }

    @Test func aMonitorOfYourOwnDoesNotFollowTheSystem() async {
        let expected = Self.isSystemThrottling
        let monitor = AnimatedImagePowerMonitor(isThrottling: !expected)
        // A monitor that does follow the system, out of step the same way, to
        // tell when the notification has been delivered.
        let witness = AnimatedImagePowerMonitor()
        witness.setThrottling(!expected)

        NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: ProcessInfo.processInfo)
        for _ in 0..<100 where witness.isThrottling != expected {
            await Task.yield()
        }

        #expect(witness.isThrottling == expected)
        #expect(monitor.isThrottling == !expected)
    }

    // MARK: Helpers

    /// What the system is asking for as the monitor reads it: Low Power Mode,
    /// or a device hot enough to be throttling itself – `.fair` is merely warm.
    private static var isSystemThrottling: Bool {
        let processInfo = ProcessInfo.processInfo
        switch processInfo.thermalState {
        case .serious, .critical: return true
        default: return processInfo.isLowPowerModeEnabled
        }
    }

    /// A player of an animation whose every frame lasts the given delay.
    private func makePlayer(
        delay: TimeInterval,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options(),
        power: AnimatedImagePowerMonitor
    ) -> (player: AnimatedImagePlayer, clock: ManualClock) {
        let source = Test.animatedGIFSource(delays: Array(repeating: delay, count: 4))
        let clock = ManualClock()
        let player = AnimatedImagePlayer(source: source, options: options, clock: clock, pool: pool, power: power)
        return (player, clock)
    }
}
