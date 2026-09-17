// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// What ``demoWait(timeout:every:whenCancelled:isolation:until:)`` does once
/// its task is cancelled.
enum DemoWaitCancellation {
    /// Gives up at once.
    case stop
    /// Waits on until the condition holds or the time is up: for a clean-up
    /// that has to see its wait through after a Stop.
    case keepWaiting
}

/// Checks `condition` every `interval` until it holds or `timeout` passes,
/// and returns whether it held.
///
/// It is the loop the Lab's runs wait in, without its trap: in a cancelled
/// task, `try? await Task.sleep(for:)` throws at once rather than suspending,
/// so a loop that doesn't stop at the cancel spins until its timeout – on
/// the main thread, for a caller there. This one stops, or, with
/// `.keepWaiting`, sleeps in a task of its own, which the cancel doesn't
/// reach.
@discardableResult
func demoWait(
    timeout: Duration,
    every interval: Duration = .milliseconds(20),
    whenCancelled cancellation: DemoWaitCancellation = .stop,
    isolation: isolated (any Actor)? = #isolation,
    until condition: () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        guard clock.now < deadline else { return false }
        if !Task.isCancelled {
            try? await Task.sleep(for: interval)
        } else if cancellation == .keepWaiting {
            await Task.detached { try? await Task.sleep(for: interval) }.value
        } else {
            return false
        }
    }
    return true
}
