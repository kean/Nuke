// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

extension ImagePipeline.Diagnostics {
    /// What the pipeline is doing right now: the tasks in flight, how much
    /// work is waiting in each queue, and how full the memory cache is.
    ///
    /// It answers the question a record of a finished task can't: why a task
    /// hasn't finished yet. It works with diagnostics off, and the only cost
    /// is the call.
    ///
    /// ```swift
    /// print(await ImagePipeline.shared.diagnostics.snapshot())
    /// ```
    public func snapshot() async -> Snapshot {
        await Task { @ImagePipelineActor in pipeline.makeSnapshot() }.value
    }

    /// See ``ImagePipeline/Diagnostics-swift.struct/snapshot()``.
    public struct Snapshot: Sendable, CustomStringConvertible {
        /// The pipeline it was taken from.
        public let pipelineID: UUID
        /// `true` if the pipeline was invalidated, and fails every new task.
        public let isInvalidated: Bool
        /// The tasks that haven't finished, oldest first.
        public let tasks: [ActiveTask]
        /// The queues in ``ImagePipeline/Configuration-swift.struct``.
        public let queues: [Queue]
        /// `nil` if the pipeline has no memory cache, or if it's a custom one.
        public let memoryCache: MemoryCache?
        /// `true` if the pipeline has a ``ImagePipeline/Configuration-swift.struct/dataCache``.
        /// The default one doesn't, and relies on the `URLCache` of the
        /// ``DataLoader``.
        public let hasDataCache: Bool

        /// A task that hasn't finished.
        public struct ActiveTask: Sendable {
            /// ``ImageTask/taskId``.
            public let taskID: UInt64
            public let kind: ImageTask.Metrics.Kind
            /// The URL with no query, which can carry a token, or the
            /// ``ImageRequest/imageID`` of a request that has no URL.
            public let resource: String?
            public let priority: ImageRequest.Priority
            public let progress: ImageTask.Progress
            /// The time since the task was created. `nil` when diagnostics
            /// are off, because nothing recorded it.
            public let age: TimeInterval?
            /// ``ImageTask/Status/retryCount``.
            public let retryCount: Int
            /// `true` if an attempt failed, and the load is waiting for the
            /// time to retry or for the device to get back online. No queue
            /// is holding it up.
            public let isWaitingForRetry: Bool
        }

        /// One of the queues in ``ImagePipeline/Configuration-swift.struct``.
        public struct Queue: Sendable {
            /// The name of the property, such as `"dataLoadingQueue"`.
            public let name: String
            public let runningCount: Int
            public let pendingCount: Int
            /// ``TaskQueue/maxConcurrentTaskCount``.
            public let limit: Int
            /// ``TaskQueue/isSuspended``. A queue that's suspended starts nothing.
            public let isSuspended: Bool
        }

        /// How full an ``ImageCache`` is.
        public struct MemoryCache: Sendable {
            public let count: Int
            public let cost: Int
            public let countLimit: Int
            public let costLimit: Int
        }

        /// A report to read in a console or in the debugger.
        public var description: String {
            let taskCount = "\(tasks.count) task\(tasks.count == 1 ? "" : "s")"
            var lines = ["ImagePipeline \(pipelineID.uuidString.prefix(8)) · \(taskCount)\(isInvalidated ? " · invalidated" : "")"]

            let nameWidth = queues.map(\.name.count).max() ?? 0
            lines += queues.map { queue in
                var line = "  \(queue.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0))  \(queue.runningCount)/\(queue.limit) running"
                if queue.pendingCount > 0 {
                    line += " · \(queue.pendingCount) pending"
                }
                return line + (queue.isSuspended ? " · suspended" : "")
            }

            if let cache = memoryCache {
                lines.append("memory cache: \(cache.count) image\(cache.count == 1 ? "" : "s") · \(Formatter.bytes(cache.cost)) of \(Formatter.bytes(cache.costLimit))")
            } else {
                lines.append("memory cache: none")
            }
            lines.append("disk cache: \(hasDataCache ? "DataCache" : "none")")

            // The oldest are the ones worth reading: nothing lands in this
            // report unless the pipeline is stuck or busy.
            lines += tasks.prefix(Self.maxPrintedTaskCount).map(\.line)
            if tasks.count > Self.maxPrintedTaskCount {
                lines.append("… and \(tasks.count - Self.maxPrintedTaskCount) more")
            }
            return lines.joined(separator: "\n")
        }

        private static let maxPrintedTaskCount = 50
    }
}

extension ImagePipeline.Diagnostics.Snapshot.ActiveTask {
    /// `#12 · normal · 45% · 1.2 s · 1 retry · waiting to retry · https://example.com/image.jpeg`
    fileprivate var line: String {
        var parts = ["#\(taskID)"]
        if kind != .image {
            parts.append(kind.rawValue)
        }
        parts.append(priority.name)
        if progress.total > 0 {
            parts.append("\(Int((progress.fraction * 100).rounded()))%")
        }
        parts += age.map { [String(format: "%.1f s", $0)] } ?? []
        if retryCount > 0 {
            parts.append(retryCount == 1 ? "1 retry" : "\(retryCount) retries")
        }
        if isWaitingForRetry {
            parts.append("waiting to retry")
        }
        parts += resource.map { [$0] } ?? []
        return "  " + parts.joined(separator: " · ")
    }
}

// MARK: - Debugger

extension ImagePipeline.Diagnostics: CustomDebugStringConvertible {
    /// The ``ImagePipeline/Diagnostics-swift.struct/snapshot()`` for a place
    /// that can't `await`, which is where it's needed most:
    ///
    /// ```
    /// (lldb) po ImagePipeline.shared.diagnostics
    /// ```
    ///
    /// The state belongs to ``ImagePipelineActor``, so this blocks the current
    /// thread until the actor reads it, for up to two seconds. lldb lets the
    /// other threads run while it evaluates an expression, unless the program
    /// is stopped on the actor itself, which is the case that times out.
    public var debugDescription: String {
        let semaphore = DispatchSemaphore(value: 0)
        let description = OSAllocatedUnfairLock<String?>(initialState: nil)
        Task { @ImagePipelineActor [pipeline] in
            let value = pipeline.makeSnapshot().description
            description.withLock { $0 = value }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 2) == .success, let value = description.withLock({ $0 }) else {
            return "ImagePipeline: no snapshot, the pipeline actor didn't respond. If the program is stopped on it, step out of it and try again."
        }
        return value
    }
}

// MARK: - ImagePipeline

extension ImagePipeline {
    func makeSnapshot() -> Diagnostics.Snapshot {
        let now = recorder?.now
        let tasks = activeTasks.map { task in
            let status = task.status
            return Diagnostics.Snapshot.ActiveTask(
                taskID: task.taskId,
                kind: task._kind,
                resource: task.request.url?.redactedDescription ?? task.request.imageID,
                priority: status.priority,
                progress: status.progress,
                age: task._createdAt.flatMap { createdAt in now.map { $0 - createdAt } },
                retryCount: status.retryCount,
                isWaitingForRetry: task._isWaitingForRetry
            )
        }
        let queues = [
            ("dataLoadingQueue", configuration.dataLoadingQueue),
            ("imageDecodingQueue", configuration.imageDecodingQueue),
            ("imageEncodingQueue", configuration.imageEncodingQueue),
            ("imageProcessingQueue", configuration.imageProcessingQueue),
            ("imageDecompressingQueue", configuration.imageDecompressingQueue)
        ].map { name, queue in
            Diagnostics.Snapshot.Queue(name: name, runningCount: queue.runningCount, pendingCount: queue.pendingCount, limit: queue.maxConcurrentTaskCount, isSuspended: queue.isSuspended)
        }
        let memoryCache = (configuration.imageCache as? ImageCache).map {
            Diagnostics.Snapshot.MemoryCache(count: $0.totalCount, cost: $0.totalCost, countLimit: $0.countLimit, costLimit: $0.costLimit)
        }
        return Diagnostics.Snapshot(pipelineID: id, isInvalidated: isInvalidated, tasks: tasks, queues: queues, memoryCache: memoryCache, hasDataCache: configuration.dataCache != nil)
    }
}
