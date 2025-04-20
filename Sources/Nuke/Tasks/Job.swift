// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

@ImagePipelineActor
protocol JobSubscriber<Value>: AnyObject {
    associatedtype Value: Sendable

    func receive(_ event: Job<Value>.Event)

    func addTasks(to output: inout [ImageTask])
}

/// Represents a unit of work performed by the image pipeline. The same unit
/// can have multiple subscribers: image tasks or other jobs.
@ImagePipelineActor
class Job<Value: Sendable>: JobProtocol {
    enum Event {
        case value(Value, isCompleted: Bool)
        case progress(JobProgress)
        case error(ImageTask.Error)
    }

    private struct Subscription {
        var subscriber: any JobSubscriber<Value>
        var priority: JobPriority
    }

    // In most situations, especially for intermediate tasks, the almost almost
    // only one subscription.
    private var inlineSubscription: Subscription?
    private var subscriptions: [TaskSubscriptionKey: Subscription]? // Create lazily
    private var nextSubscriptionKey = 0

    /// Returns `true` if the task was either cancelled, or was completed.
    private(set) var isDisposed = false
    private var isStarted = false

    /// Gets called when the task is either cancelled, or was completed.
    var onDisposed: (@ImagePipelineActor @Sendable () -> Void)?

    var priority: JobPriority = .normal {
        didSet {
            guard oldValue != priority else { return }
            operation?.priority = priority
            dependency?.setPriority(priority)
        }
    }

    /// A task might have a dependency. The task automatically unsubscribes
    /// from the dependency when it gets cancelled, and also updates the
    /// priority of the subscription to the dependency when its own
    /// priority is updated.
    var dependency: TaskSubscription? {
        didSet {
            dependency?.setPriority(priority)
        }
    }

    var operation: WorkQueue.Operation?

    /// Returns all tasks registered for the current job, directly or indirectly.
    var tasks: [ImageTask] {
        var tasks: [ImageTask] = []
        addTasks(to: &tasks)
        return tasks
    }

    /// Override this to start image task. Only gets called once.
    func start() {}

    init() {}

    // MARK: - Managing Observers

    /// - notes: Returns `nil` if the task was disposed.
    func subscribe(priority: JobPriority = .normal, subscriber: any JobSubscriber<Value>) -> TaskSubscription? {
        guard !isDisposed else { return nil }

        let subscriptionKey = nextSubscriptionKey
        nextSubscriptionKey += 1
        let subscription = TaskSubscription(task: self, key: subscriptionKey)

        if subscriptionKey == 0 {
            inlineSubscription = Subscription(subscriber: subscriber, priority: priority)
        } else {
            if subscriptions == nil { subscriptions = [:] }
            subscriptions![subscriptionKey] = Subscription(subscriber: subscriber, priority: priority)
        }

        updatePriority(suggestedPriority: priority)

        if !isStarted {
            isStarted = true
            start()
        }

        // The task may have been completed synchronously by `starter`.
        guard !isDisposed else { return nil }
        return subscription
    }

    // MARK: - TaskSubscriptionDelegate

    fileprivate func setPriority(_ priority: JobPriority, for key: TaskSubscriptionKey) {
        guard !isDisposed else { return }

        if key == 0 {
            inlineSubscription?.priority = priority
        } else {
            subscriptions![key]?.priority = priority
        }
        updatePriority(suggestedPriority: priority)
    }

    fileprivate func unsubscribe(key: TaskSubscriptionKey) {
        if key == 0 {
            guard inlineSubscription != nil else { return }
            inlineSubscription = nil
        } else {
            guard subscriptions!.removeValue(forKey: key) != nil else { return }
        }

        guard !isDisposed else { return }

        if inlineSubscription == nil && subscriptions?.isEmpty ?? true {
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

        forEachSubscription {
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
        inlineSubscription = nil
        subscriptions = nil
        onDisposed?()
    }

    // MARK: - Priority

    private func updatePriority(suggestedPriority: JobPriority?) {
        if let suggestedPriority, suggestedPriority >= priority {
            // No need to recompute, won't go higher than that
            priority = suggestedPriority
            return
        }
        var newPriority: JobPriority?
        forEachSubscription {
            if newPriority == nil {
                newPriority = $0.priority
            } else if $0.priority > newPriority! {
                newPriority = $0.priority
            }
        }
        self.priority = newPriority ?? .normal
    }

    // MARK: - Subscribers

    func addTasks(to output: inout [ImageTask]) {
        forEachSubscription {
            $0.subscriber.addTasks(to: &output)
        }
    }

    private func forEachSubscription(_ closure: (Subscription) -> Void) {
        if let inlineSubscription {
            closure(inlineSubscription)
        }
        if let subscriptions {
            for (_, value) in subscriptions {
                closure(value)
            }
        }
    }
}

typealias JobProgress = ImageTask.Progress
typealias JobPriority = ImageRequest.Priority

// MARK: - TaskSubscription

/// Represents a subscription to a task. The observer must retain a strong
/// reference to a subscription.
@ImagePipelineActor
struct TaskSubscription {
    private let task: any JobProtocol
    private let key: TaskSubscriptionKey

    fileprivate init(task: any JobProtocol, key: TaskSubscriptionKey) {
        self.task = task
        self.key = key
    }

    /// Removes the subscription from the task. The observer won't receive any
    /// more events from the task.
    ///
    /// If there are no more subscriptions attached to the task, the task gets
    /// cancelled along with its dependencies. The cancelled task is
    /// marked as disposed.
    func unsubscribe() {
        task.unsubscribe(key: key)
    }

    /// Updates the priority of the subscription. The priority of the task is
    /// calculated as the maximum priority out of all of its subscription. When
    /// the priority of the task is updated, the priority of a dependency also is.
    ///
    /// - note: The priority also automatically gets updated when the subscription
    /// is removed from the task.
    func setPriority(_ priority: JobPriority) {
        task.setPriority(priority, for: key)
    }
}

@ImagePipelineActor
private protocol JobProtocol: AnyObject {
    func unsubscribe(key: TaskSubscriptionKey)
    func setPriority(_ priority: JobPriority, for observer: TaskSubscriptionKey)
}

private typealias TaskSubscriptionKey = Int
