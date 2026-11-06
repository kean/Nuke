// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Network
import os

/// What the monitor observes: the network path of the device in an app, and a
/// script in the tests.
protocol ConnectivityObserving: Sendable {
    var isOnline: Bool { get }

    /// Starts observing. `onChange` is called with the initial state as well.
    func start(onChange: @escaping @Sendable () -> Void)
    func stop()
}

/// Lets the retries wait for the device to get back online.
///
/// It only observes the network while a retry is waiting: a failed load is the
/// one thing in the pipeline that needs to know, and most never come here.
@ImagePipelineActor
final class ConnectivityMonitor {
    nonisolated static let shared = ConnectivityMonitor { NetworkPathObserver() }

    private let makeObserver: @Sendable () -> any ConnectivityObserving
    private var observer: (any ConnectivityObserving)?
    /// Changes with every observer, so that a late call from one that was
    /// already stopped is ignored.
    private var observerID = 0
    /// `false` until the observer reports the state for the first time.
    private var isStateKnown = false
    private var waiters: [Int: UnsafeContinuation<Bool, Never>] = [:]
    /// The waits whose time ran out before the observer reported anything.
    /// `NWPathMonitor` takes a moment to report the first time, and until it
    /// does, nothing says that the device is offline, so they end with that
    /// report, whatever it says.
    private var expiredWaiters: Set<Int> = []
    private var nextWaiterID = 0

    nonisolated init(makeObserver: @escaping @Sendable () -> any ConnectivityObserving) {
        self.makeObserver = makeObserver
    }

    /// Returns `true` when the device is online, or `false` if it still isn't
    /// after `timeout` seconds or if the calling task is cancelled.
    func waitUntilOnline(timeout: TimeInterval) async -> Bool {
        let id = nextWaiterID
        nextWaiterID += 1
        let timer = Task { @ImagePipelineActor in
            await Task.sleep(seconds: timeout)
            guard !Task.isCancelled else { return }
            self.waiterDidTimeOut(id)
        }
        let isOnline = await withTaskCancellationHandler {
            await withUnsafeContinuation { continuation in
                waiters[id] = continuation
                startObservingIfNeeded()
            }
        } onCancel: {
            timer.cancel()
            Task { @ImagePipelineActor in self.finishWaiter(id, isOnline: false) }
        }
        timer.cancel()
        return isOnline
    }

    private func startObservingIfNeeded() {
        guard observer == nil else { return }
        observerID += 1
        isStateKnown = false
        let id = observerID
        let observer = makeObserver()
        self.observer = observer
        observer.start { [weak self] in
            Task { @ImagePipelineActor in self?.didChangeConnectivity(observerID: id) }
        }
    }

    private func didChangeConnectivity(observerID: Int) {
        // Read the state instead of passing it along: the hops are unordered.
        guard observerID == self.observerID, let observer else { return }
        isStateKnown = true
        let isOnline = observer.isOnline
        for id in waiters.keys where isOnline || expiredWaiters.contains(id) {
            finishWaiter(id, isOnline: isOnline)
        }
    }

    private func waiterDidTimeOut(_ id: Int) {
        guard isStateKnown else {
            expiredWaiters.insert(id)
            return
        }
        finishWaiter(id, isOnline: false)
    }

    private func finishWaiter(_ id: Int, isOnline: Bool) {
        expiredWaiters.remove(id)
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.resume(returning: isOnline)
        if waiters.isEmpty {
            observer?.stop()
            observer = nil
        }
    }
}

private final class NetworkPathObserver: ConnectivityObserving {
    private let monitor = NWPathMonitor()
    private let _isOnline = OSAllocatedUnfairLock(initialState: false)

    var isOnline: Bool { _isOnline.withLock { $0 } }

    func start(onChange: @escaping @Sendable () -> Void) {
        let isOnline = _isOnline
        monitor.pathUpdateHandler = { path in
            isOnline.withLock { $0 = path.status == .satisfied }
            onChange()
        }
        monitor.start(queue: DispatchQueue(label: "com.github.kean.Nuke.ConnectivityMonitor"))
    }

    func stop() {
        monitor.cancel()
    }
}
