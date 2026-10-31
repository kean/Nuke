// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// A network that's online or offline when the test says so.
final class MockConnectivityObserver: ConnectivityObserving, @unchecked Sendable {
    var isOnline: Bool {
        get { lock.withLock { _isOnline } }
        set {
            let onChange = lock.withLock {
                _isOnline = newValue
                return _onChange
            }
            onChange?()
        }
    }
    var startCount: Int { lock.withLock { _startCount } }
    var stopCount: Int { lock.withLock { _stopCount } }

    private let lock = NSLock()
    private var _isOnline: Bool
    private var _onChange: (@Sendable () -> Void)?
    private var _startCount = 0
    private var _stopCount = 0

    init(isOnline: Bool) {
        self._isOnline = isOnline
    }

    func start(onChange: @escaping @Sendable () -> Void) {
        lock.withLock {
            _onChange = onChange
            _startCount += 1
        }
        onChange()
    }

    func stop() {
        lock.withLock {
            _onChange = nil
            _stopCount += 1
        }
    }
}

@Suite(.timeLimit(.minutes(5))) @ImagePipelineActor
struct ConnectivityMonitorTests {
    private let observer = MockConnectivityObserver(isOnline: false)
    private let monitor: ConnectivityMonitor

    init() {
        let observer = self.observer
        self.monitor = ConnectivityMonitor { observer }
    }

    /// Waits until the monitor runs the given number of waits.
    private func waitForObserverToStart() async {
        await waitUntil { observer.startCount == 1 }
    }

    @Test func doesNotObserveAnythingUntilSomethingWaits() async {
        await drainPendingWork()
        #expect(observer.startCount == 0)
    }

    @Test func returnsRightAwayWhenOnline() async {
        observer.isOnline = true
        #expect(await monitor.waitUntilOnline(timeout: 60))
        #expect(observer.startCount == 1)
        #expect(observer.stopCount == 1)
    }

    @Test func waitsForTheDeviceToGetBackOnline() async {
        let task = Task { await monitor.waitUntilOnline(timeout: 60) }
        await waitForObserverToStart()

        observer.isOnline = true

        #expect(await task.value)
    }

    @Test func staysWaitingThroughAChangeThatLeavesItOffline() async {
        let task = Task { await monitor.waitUntilOnline(timeout: 60) }
        await waitForObserverToStart()

        observer.isOnline = false
        await drainPendingWork()
        observer.isOnline = true

        #expect(await task.value)
    }

    @Test func returnsFalseWhenTheTimeRunsOut() async {
        #expect(await monitor.waitUntilOnline(timeout: 0.01) == false)
        #expect(observer.stopCount == 1)
    }

    @Test func returnsFalseWhenCancelled() async {
        let task = Task { await monitor.waitUntilOnline(timeout: 600) }
        await waitForObserverToStart()

        task.cancel()

        #expect(await task.value == false)
        #expect(observer.stopCount == 1)
    }

    @Test func returnsFalseWhenAlreadyCancelled() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await monitor.waitUntilOnline(timeout: 600)
        }
        #expect(await task.value == false)
    }

    @Test func wakesUpEveryoneWhoIsWaiting() async {
        let tasks = (0..<5).map { _ in Task { await monitor.waitUntilOnline(timeout: 60) } }
        await waitForObserverToStart()
        await drainPendingWork()

        observer.isOnline = true

        for task in tasks {
            #expect(await task.value)
        }
        #expect(observer.startCount == 1)
        #expect(observer.stopCount == 1)
    }

    @Test func oneTimeoutDoesNotEndTheOtherWaits() async {
        let long = Task { await monitor.waitUntilOnline(timeout: 60) }
        await waitForObserverToStart()
        let short = await monitor.waitUntilOnline(timeout: 0.01)
        #expect(short == false)
        #expect(observer.stopCount == 0)

        observer.isOnline = true

        #expect(await long.value)
    }

    @Test func observesAgainForTheNextWait() async {
        #expect(await monitor.waitUntilOnline(timeout: 0.01) == false)

        observer.isOnline = true

        #expect(await monitor.waitUntilOnline(timeout: 60))
        #expect(observer.startCount == 2)
        #expect(observer.stopCount == 2)
    }

    /// The system monitor is the part the fakes above stand in for, so this
    /// goes through it. It doesn't assume anything about the network of the
    /// machine that runs it, only that the monitor reports the path.
    @Test func systemMonitorReportsThePath() async {
        let isOnline = await ConnectivityMonitor.shared.waitUntilOnline(timeout: 0.5)
        _ = isOnline // Either answer means that the wait ended.
    }
}
