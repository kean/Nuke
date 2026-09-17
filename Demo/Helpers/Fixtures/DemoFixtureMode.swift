// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Observation
import os

/// Whether the demo is offline: every image served by fixtures, and no
/// request sent to the network.
///
/// Offline, ``DemoImages`` hands out fixture URLs, so the screens opened next
/// load fixtures and keep them in their caches under keys of their own, apart
/// from the photos. The probe of every pipeline sends every request to a
/// ``DemoFixtureLoader``, so a network URL a screen is still holding is
/// answered by the fixture that stands in for it, or fails.
///
/// `-demoFixtures offline` starts the app offline, and so does
/// `-demoDeterministic 1`. The **Fixture Mode** screen in the Lab switches it
/// while the app runs, with no pipeline rebuilt: the probe reads it for each
/// download. A screen already open keeps the URLs it was built with.
///
/// Lab screens that load images use fixtures whatever the mode – see
/// ``DemoImageSource``.
@MainActor @Observable
final class DemoFixtureMode {
    static let shared = DemoFixtureMode()

    var isOffline: Bool {
        didSet {
            guard isOffline != oldValue else { return }
            let isOffline = isOffline
            Self.state.withLock { $0 = isOffline }
            Self.logger.info("The demo is \(isOffline ? "offline" : "online", privacy: .public).")
        }
    }

    private init() {
        isOffline = Self.state.withLock { $0 }
    }

    /// ``isOffline``, from any thread: what the pipelines read.
    nonisolated static var isOffline: Bool {
        state.withLock { $0 }
    }

    private nonisolated static let state = OSAllocatedUnfairLock(initialState: DemoLaunchOptions.current.isOffline)

    private nonisolated static let logger = Logger(subsystem: "com.github.kean.NukeDemo", category: "Fixtures")
}
