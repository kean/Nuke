// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct TestExpectationTests {
    /// `NotificationCenter` can deliver the notification on another thread before
    /// `addObserver` returns, so the expectation has to survive being fulfilled
    /// while it is still being created.
    @Test func notificationIsDeliveredWhileExpectationIsCreated() async {
        let name = Notification.Name("com.github.kean.Nuke.Tests.TestExpectationTests.\(UUID().uuidString)")
        let isPosting = Nuke.Mutex(value: true)
        let thread = Thread {
            while isPosting.value {
                NotificationCenter.default.post(name: name, object: nil)
            }
        }
        thread.start()
        defer { isPosting.withLock { $0 = false } }

        for _ in 0..<100 {
            await notification(name)
        }
    }
}
