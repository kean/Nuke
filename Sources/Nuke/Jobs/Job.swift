// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

// TODO: separate priority from addSubscribedTasks and (probably) remove priorit entirey
/// A subscriber determines the priority of the job (together with other subscribers).
@ImagePipelineActor
protocol JobOwner {
    var priority: JobPriority { get }
    func addSubscribedTasks(to output: inout [ImageTask])
}

/// A subscriber that also receives events emitted by the job.
@ImagePipelineActor
protocol JobSubscriber<Value>: JobOwner {
    associatedtype Value: Sendable

    func receive(_ event: Job<Value>.Event)
}

// TODO: can we remove some of these?
@ImagePipelineActor
protocol JobDelegate: AnyObject {
    func jobDisposed(_ job: any JobProtocol)
    func job(_ job: any JobProtocol, didUpdatePriority newPriority: JobPriority, from oldPriority: JobPriority)
}

/// Represents a unit of work performed by the image pipeline.
///
/// A single job can have many subscribers. The priority of the job is automatically
/// set to the highest priority of its subscribers.
@ImagePipelineActor
class Job<Value: Sendable>: JobProtocol, JobOwner {
    enum Event {
        case value(Value, isCompleted: Bool)
        case progress(JobProgress)
        case error(ImageTask.Error)
    }

    private struct Subscriber {
        var subscriber: any JobSubscriber<Value>
    }

    private var subscriptions = JobSubsciberSet<Subscriber>()

    /// Returns `true` if the job was either cancelled, or was completed.
    private(set) var isDisposed = false
    private(set) var isStarted = false
    private var isEnqueued = false

    /// Gets called when the job is either cancelled, or was completed.
    var onDisposed: (@ImagePipelineActor @Sendable () -> Void)?

    private(set) var priority: JobPriority = .normal {
        didSet {
            guard oldValue != priority else { return }
            operation?.didChangePriority(priority)
            dependency?.didChangePriority(priority)
            delegate?.job(self, didUpdatePriority: priority, from: oldValue)
        }
    }

    /// A queue on which to schedule the job.
    ///
    /// The job is scheduled automatically as soon as the first subscriber is added.
    /// It ensures that if it completes synchronously, the events are still
    /// delivered, and the job gets scheduled with the initial priority
    /// based on the subscriber.
    weak var queue: JobQueue?

    weak var delegate: JobDelegate?

    /// A job might have a dependency. The job automatically unsubscribes
    /// from the dependency when it gets cancelled, and also updates the
    /// priority of the subscription to the dependency when its own
    /// priority is updated.
    var dependency: JobSubscription? {
        didSet {
            dependency?.didChangePriority(priority)
        }
    }

    var operation: JobSubscription?

    /// Returns all tasks registered for the current job, directly or indirectly.
    var tasks: [ImageTask] {
        var tasks: [ImageTask] = []
        addSubscribedTasks(to: &tasks)
        return tasks
    }

    private var starter: (@ImagePipelineActor @Sendable (Job<Value>) -> Void)?

    init(_ starter: @ImagePipelineActor @Sendable @escaping (Job<Value>) -> Void) {
        self.starter = starter
    }

    init() {}

    // MARK: - Hooks

    /// Override this to start the job. Only gets called once.
    func start() {}

    // TODO: overriding is bad
    func onCancel() {
        terminate(reason: .cancelled)
    }

    // MARK: - Stat

    /// - warning: Do not call this directly.
    func startIfNeeded() {
        guard !isStarted else { return }
        isStarted = true
        start()
    }

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

        if !isEnqueued {
            isEnqueued = true
            if let queue {
                queue.enqueue(self)
            } else {
                startIfNeeded()
            }
        }

        // The job may have been completed synchronously by `starter`.
        guard !isDisposed else { return nil }
        return JobSubscription(job: self, key: index)
    }

    // MARK: - JobSubscriptionDelegate

    func didChangePriority(_ priority: JobPriority, for key: JobSubscriptionKey) {
        guard !isDisposed else { return }
        updatePriority(suggestedPriority: priority)
    }

    func unsubscribe(key: JobSubscriptionKey) {
        subscriptions.remove(at: key)
        guard !isDisposed else { return }
        // swiftlint:disable:next empty_count
        if subscriptions.count == 0 {
            onCancel()
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

    /// A convenience method that send a terminal event depending on the result.
    func finish(with result: Result<Value, ImageTask.Error>) {
        switch result {
        case .success(let value):
            send(value: value, isCompleted: true)
        case .failure(let error):
            send(error: error)
        }
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
            operation?.unsubscribe()
            dependency?.unsubscribe()
        }
        subscriptions = .init()
        onDisposed?()
        delegate?.jobDisposed(self)
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
    /// cancelled along with its dependencies. The cancelled job is
    /// marked as disposed.
    func unsubscribe() {
        job.unsubscribe(key: key)
    }

    /// Updates the priority of the subscription. The priority of the job is
    /// calculated as the maximum priority out of all of its subscription. When
    /// the priority of the job is updated, the priority of a dependency also is.
    ///
    /// - note: The priority also automatically gets updated when the subscription
    /// is removed from the job.
    func didChangePriority(_ priority: JobPriority) {
        job.didChangePriority(priority, for: key)
    }
}

// TODO: add separate JobSubscription.Delegate
@ImagePipelineActor
protocol JobProtocol: AnyObject, Sendable {
    var priority: JobPriority { get }
    var isStarted: Bool { get }
    var queue: JobQueue? { get set }

    func startIfNeeded()
    func unsubscribe(key: JobSubscriptionKey)
    func didChangePriority(_ priority: JobPriority, for key: JobSubscriptionKey)
}

typealias JobSubscriptionKey = Int
