// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

@ImagePipelineActor
protocol JobSubscriber<Value>: AnyObject {
    associatedtype Value: Sendable

    var priority: JobPriority { get }

    func receive(_ event: Job<Value>.Event)

    func addSubscribedTasks(to output: inout [ImageTask])
}

/// Represents a unit of work performed by the image pipeline. The same unit
/// can have multiple subscribers: image jibs or other jobs.
@ImagePipelineActor
class Job<Value: Sendable>: JobProtocol {
    enum Event {
        case value(Value, isCompleted: Bool)
        case progress(JobProgress)
        case error(ImageTask.Error)
    }

    private struct Subscriber {
        var subscriber: any JobSubscriber<Value>
    }

    private var subscriptions = JobSubsciberSet<Subscriber>()

    /// Returns `true` if the jib was either cancelled, or was completed.
    private(set) var isDisposed = false
    private var isStarted = false

    /// Gets called when the jib is either cancelled, or was completed.
    var onDisposed: (@ImagePipelineActor @Sendable () -> Void)?

    var priority: JobPriority = .normal {
        didSet {
            guard oldValue != priority else { return }
            operation?.priority = priority
            dependency?.didChangePriority(priority)
        }
    }

    /// A job might have a dependency. The job automatically unsubscribes
    /// from the dependency when it gets cancelled, and also updates the
    /// priority of the subscription to the dependency when its own
    /// priority is updated.
    var dependency: JobSubscription? {
        didSet {
            dependency?.didChangePriority(priority)
        }
    }

    var operation: WorkQueue.Operation?

    /// Returns all tasks registered for the current job, directly or indirectly.
    var tasks: [ImageTask] {
        var tasks: [ImageTask] = []
        addSubscribedTasks(to: &tasks)
        return tasks
    }

    init() {}

    // MARK: - Hooks

    /// Override this to start the job. Only gets called once.
    func start() {}

    // MARK: - Subscribers

    /// - notes: Returns `nil` if the job was disposed.
    func subscribe(_ subscriber: any JobSubscriber<Value>) -> JobSubscription? {
        guard !isDisposed else { return nil }

        let index = subscriptions.add(Subscriber(subscriber: subscriber))

        if subscriptions.count == 1 {
            priority = subscriber.priority
        } else {
            updatePriority(suggestedPriority: subscriber.priority)
        }

        if !isStarted {
            isStarted = true
            start()
        }

        // The job may have been completed synchronously by `starter`.
        guard !isDisposed else { return nil }
        return JobSubscription(job: self, key: index)
    }

    // MARK: - JobSubscriptionDelegate

    fileprivate func didChangePriority(_ priority: JobPriority, for key: JobSubscriptionKey) {
        guard !isDisposed else { return }
        updatePriority(suggestedPriority: priority)
    }

    fileprivate func unsubscribe(key: JobSubscriptionKey) {
        subscriptions.remove(at: key)
        guard !isDisposed else { return }
        // swiftlint:disable:next empty_count
        if subscriptions.count == 0 {
            terminate(reason: .cancelled)
        } else {
            updatePriority(suggestedPriority: nil)
        }
    }

    // MARK: - Sending Events

    func send(value: Value, isCompleted: Bool = false) {
        send(event: .value(value, isCompleted: isCompleted))
    }

    func send(error: ImageTask.Error) {
        send(event: .error(error))
    }

    func send(progress: JobProgress) {
        send(event: .progress(progress))
    }

    private func send(event: Event) {
        guard !isDisposed else { return }

        subscriptions.forEach {
            $0.subscriber.receive(event)
        }

        switch event {
        case let .value(_, isCompleted):
            if isCompleted {
                terminate(reason: .finished)
            }
        case .progress:
            break // Simply send the event
        case .error:
            terminate(reason: .finished)
        }
    }

    // MARK: - Termination

    private enum TerminationReason {
        case finished, cancelled
    }

    private func terminate(reason: TerminationReason) {
        guard !isDisposed else { return }
        isDisposed = true

        if reason == .cancelled {
            operation?.cancel()
            dependency?.unsubscribe()
        }
        subscriptions = .init()
        onDisposed?()
    }

    // MARK: - Priority

    private func updatePriority(suggestedPriority: JobPriority?) {
        if let suggestedPriority, suggestedPriority >= priority {
            // No need to recompute, won't go higher than that
            priority = suggestedPriority
            return
        }
        var newPriority: JobPriority = .veryLow
        subscriptions.forEach {
            newPriority = max(newPriority, $0.subscriber.priority)
        }
        self.priority = newPriority
    }

    // MARK: - Subscribers

    func addSubscribedTasks(to output: inout [ImageTask]) {
        subscriptions.forEach {
            $0.subscriber.addSubscribedTasks(to: &output)
        }
    }
}

typealias JobProgress = ImageTask.Progress
typealias JobPriority = ImageRequest.Priority

// MARK: - JobSubscription

/// Represents a subscription to a job. The observer must retain a strong
/// reference to a subscription.
@ImagePipelineActor
struct JobSubscription {
    private let job: any JobProtocol
    private let key: JobSubscriptionKey

    fileprivate init(job: any JobProtocol, key: JobSubscriptionKey) {
        self.job = job
        self.key = key
    }

    /// Removes the subscription from the job. The observer won't receive any
    /// more events from the job.
    ///
    /// If there are no more subscriptions attached to the job, the job gets
    /// cancelled along with its dependencies. The cancelled jib is
    /// marked as disposed.
    func unsubscribe() {
        job.unsubscribe(key: key)
    }

    /// Updates the priority of the subscription. The priority of the jib is
    /// calculated as the maximum priority out of all of its subscription. When
    /// the priority of the jib is updated, the priority of a dependency also is.
    ///
    /// - note: The priority also automatically gets updated when the subscription
    /// is removed from the jib.
    func didChangePriority(_ priority: JobPriority) {
        job.didChangePriority(priority, for: key)
    }
}

@ImagePipelineActor
private protocol JobProtocol: AnyObject {
    func unsubscribe(key: JobSubscriptionKey)
    func didChangePriority(_ priority: JobPriority, for observer: JobSubscriptionKey)
}

private typealias JobSubscriptionKey = Int
