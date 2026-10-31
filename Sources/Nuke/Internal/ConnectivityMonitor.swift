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
    private var waiters: [Int: UnsafeContinuation<Bool, Never>] = [:]
    private var nextWaiterID = 0

    nonisolated init(makeObserver: @escaping @Sendable () -> any ConnectivityObserving) {
        self.makeObserver = makeObserver
    }

    /// Returns `true` when the device is online, or `false` if it still isn't
    /// after `timeout` seconds or if the calling task is cancelled.
    func waitUntilOnline(timeout: TimeInterval) async -> Bool {
        let id = nextWaiterID
        nextWaiterID += 1
        // Cancelling the timer ends the wait the same way running out of time
        // does, so there is one path out of it.
        let timer = Task { @ImagePipelineActor in
            await Task.sleep(seconds: timeout)
            self.finishWaiter(id, isOnline: false)
        }
        let isOnline = await withTaskCancellationHandler {
            await withUnsafeContinuation { continuation in
                waiters[id] = continuation
                startObservingIfNeeded()
            }
        } onCancel: {
            timer.cancel()
        }
        timer.cancel()
        return isOnline
    }

    private func startObservingIfNeeded() {
        guard observer == nil else { return }
        let observer = makeObserver()
        self.observer = observer
        observer.start { [weak self] in
            Task { @ImagePipelineActor in self?.didChangeConnectivity() }
        }
    }

    private func didChangeConnectivity() {
        // Read the state instead of passing it along: the hops are unordered,
        // and this one can even come from an observer that was already stopped.
        guard observer?.isOnline == true else { return }
        for id in waiters.keys {
            finishWaiter(id, isOnline: true)
        }
    }

    private func finishWaiter(_ id: Int, isOnline: Bool) {
        waiters.removeValue(forKey: id)?.resume(returning: isOnline)
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
