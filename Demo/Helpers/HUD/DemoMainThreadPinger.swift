// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os
import QuartzCore

/// How long the main thread takes to answer, measured from a thread of its
/// own: it hands the main queue a block, waits until the block runs, and
/// hands it the next one ``interval`` later.
///
/// A ``DemoDisplayMonitor`` sees a stall as a late frame, in whole refreshes,
/// and only while its link runs. The pinger sees it as the time a block
/// waited, to within ``interval``, whatever the display does, and it needs
/// nothing from UIKit. It also sees the main queue backed up by work that
/// runs in many short turns.
///
/// A stall is reported once it is over, when the block finally runs. The
/// cost is a block on the main queue every ``interval``, about a hundred a
/// second, and a thread that sleeps in between – only while it runs, so
/// ``start()`` it with the screen that shows it and ``stop()`` it with the
/// same screen.
final class DemoMainThreadPinger: Sendable {
    /// A block that waited longer than ``threshold``.
    struct Stall: Sendable, Equatable {
        /// When the block was handed to the main queue, in the time base of
        /// `CACurrentMediaTime()`.
        var startedAt: CFTimeInterval
        /// How long it waited.
        var duration: TimeInterval

        var endedAt: CFTimeInterval {
            startedAt + duration
        }
    }

    /// What the pinger measured since it was created or reset.
    struct Figures: Sendable, Equatable {
        /// The blocks that ran.
        var pingCount = 0
        /// The longest wait.
        var maxLatency: TimeInterval = 0
        /// The waits, added up.
        var totalLatency: TimeInterval = 0
        /// The waits longer than the threshold.
        var stallCount = 0

        var averageLatency: TimeInterval {
            pingCount > 0 ? totalLatency / Double(pingCount) : 0
        }
    }

    /// The time between an answer and the next block: the most a stall's
    /// start can be missed by.
    let interval: TimeInterval
    /// The wait above which a block counts as a stall.
    let threshold: TimeInterval

    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State: Sendable {
        var figures = Figures()
        /// The stalls not yet taken, oldest first.
        var stalls: [Stall] = []
        var isRunning = false
        /// Moved on by every start and stop, so that the thread of an
        /// earlier start ends, and a block that waited out a stop – the app
        /// in the background, say – isn't counted as a stall.
        var generation = 0
    }

    init(interval: TimeInterval = 0.01, threshold: TimeInterval = 0.016) {
        self.interval = interval
        self.threshold = threshold
    }

    /// The figures now: a copy.
    var figures: Figures {
        state.withLock { $0.figures }
    }

    /// The stalls since the last call, oldest first.
    func takeStalls() -> [Stall] {
        state.withLock { state in
            defer { state.stalls = [] }
            return state.stalls
        }
    }

    /// Starts the figures over. A pinger that runs goes on running.
    func reset() {
        state.withLock {
            $0.figures = Figures()
            $0.stalls = []
        }
    }

    /// Starts pinging. Does nothing if it is running already.
    func start() {
        let generation = state.withLock { state -> Int? in
            guard !state.isRunning else { return nil }
            state.isRunning = true
            state.generation += 1
            return state.generation
        }
        guard let generation else { return }
        let thread = Thread { [self] in
            run(generation)
        }
        thread.name = "com.github.kean.NukeDemo.MainThreadPinger"
        // Above the pipeline's work, so a busy pipeline doesn't pass for a
        // busy main thread by delaying the next block.
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Stops pinging. The thread ends once the block it is waiting for has
    /// run.
    func stop() {
        state.withLock {
            $0.isRunning = false
            $0.generation += 1
        }
    }

    private func run(_ generation: Int) {
        let answeredAt = OSAllocatedUnfairLock<CFTimeInterval>(initialState: 0)
        while state.withLock({ $0.generation == generation }) {
            let semaphore = DispatchSemaphore(value: 0)
            let sentAt = CACurrentMediaTime()
            DispatchQueue.main.async {
                answeredAt.withLock { $0 = CACurrentMediaTime() }
                semaphore.signal()
            }
            semaphore.wait()
            let latency = answeredAt.withLock { $0 } - sentAt
            let isCurrent = state.withLock { state in
                guard state.generation == generation else { return false }
                state.figures.pingCount += 1
                state.figures.maxLatency = max(state.figures.maxLatency, latency)
                state.figures.totalLatency += latency
                if latency > threshold {
                    state.figures.stallCount += 1
                    state.stalls.append(Stall(startedAt: sentAt, duration: latency))
                    if state.stalls.count > 100 {
                        state.stalls.removeFirst(state.stalls.count - 100)
                    }
                }
                return true
            }
            guard isCurrent else { return }
            Thread.sleep(forTimeInterval: interval)
        }
    }
}
