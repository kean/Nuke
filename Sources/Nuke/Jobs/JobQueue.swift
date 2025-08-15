// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Limits the number of concurrenly executed jobs.
@ImagePipelineActor
public final class JobQueue {
    /// Sets the maximum number of concurrently executed operations.
    public nonisolated var maxConcurrentJobCount: Int {
        get { _maxConcurrentJobCount.value }
        set { _maxConcurrentJobCount.value = newValue }
    }
    private let _maxConcurrentJobCount: Mutex<Int>

    /// Setting this property to true prevents the queue from starting any queued
    /// tasks, but already executing tasks continue to execute.
    var isSuspended = false {
        didSet {
            guard oldValue != isSuspended, !isSuspended else { return }
            performScheduledJobs()
        }
    }

    let scheduledJobs = (0..<JobPriority.allCases.count).map { _ in
        LinkedList<JobProtocol>()
    }

    let executingJobs = LinkedList<JobProtocol>()

    typealias JobHandle = LinkedList<JobProtocol>.Node

    enum Event {
        case added(JobHandle)
        case priorityUpdated(JobHandle, JobPriority)
        case cancelled(JobHandle)
        case disposed(JobHandle)
    }

    var onEvent: (@ImagePipelineActor (Event) -> Void)?

    nonisolated init(maxConcurrentJobCount: Int = 1) {
        self._maxConcurrentJobCount = Mutex(maxConcurrentJobCount)
    }

    /// - warning; Do not call this directly.
    func enqueue<Value>(_ job: Job<Value>) -> JobHandle {
        let handle = JobHandle(job)
        job.delegate = handle
        if !isSuspended && executingJobs.count < maxConcurrentJobCount {
            perform(handle)
        } else {
            scheduledJobs(for: handle.job.priority).prepend(handle)
        }
        onEvent?(.added(handle))
        return handle
    }

    private func perform(_ handle: JobHandle) {
        executingJobs.append(handle)
        handle.job.startIfNeeded()
    }

    private func scheduledJobs(for priority: JobPriority) -> LinkedList<JobProtocol> {
        scheduledJobs[priority.rawValue]
    }

    // MARK: - JobHandleDelegate

    func disposed(_ handle: JobHandle) {
        if handle.job.isStarted {
            executingJobs.remove(handle)
            performScheduledJobs()
        } else {
            scheduledJobs(for: handle.job.priority).remove(handle)
            onEvent?(.cancelled(handle))
        }
        handle.job.queue = nil
        onEvent?(.disposed(handle))
    }

    func job(_ handle: JobHandle, didUpdatePriority newPriority: JobPriority, from oldPriority: JobPriority) {
        guard !handle.job.isStarted else { return }
        // TODO: if we lower the priority, should it be prepended or appended? +typos
        scheduledJobs(for: oldPriority).remove(handle)
        scheduledJobs(for: newPriority).prepend(handle)
        onEvent?(.priorityUpdated(handle, newPriority))
    }

    // MARK: - Performing Scheduled Work

    /// Returns a scheduled job with the highest priority.
    private func dequeueNextJob() -> JobHandle? {
        for list in scheduledJobs.reversed() {
            if let handle = list.popLast() {
                return handle
            }
        }
        return nil
    }

    private func performScheduledJobs() {
        while !isSuspended, executingJobs.count < maxConcurrentJobCount, let job = dequeueNextJob() {
            perform(job)
        }
    }
}

@ImagePipelineActor
extension JobQueue.JobHandle: JobDelegate {
    var job: JobProtocol { value }

    func jobDisposed(_ job: any JobProtocol) {
        value.queue?.disposed(self)
    }

    func job(_ job: any JobProtocol, didUpdatePriority newPriority: JobPriority, from oldPriority: JobPriority) {
        value.queue?.job(self, didUpdatePriority: newPriority, from: oldPriority)
    }
}
