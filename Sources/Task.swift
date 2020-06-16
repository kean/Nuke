// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Represents a task with support for multiple observers, cancellation,
/// progress reporting, dependencies – everything that `ImagePipeline` needs.
///
/// A `Task` can have zero or more subscriptions (`TaskSubscription`) which can
/// be used to later unsubscribe or change the priority of the subscription.
///
/// The task has built-in support for operations (`Foundation.Operation`) – it
/// automatically cancels them, updates the priority, etc. Most steps in the
/// image pipeline are represented using Operation to take advantage of these features.
///
/// - warning: Must be thread-confined!
final class Task<Value, Error>: TaskSubscriptionDelegate {

    private struct Subscription {
        let observer: (Event) -> Void
        var priority: TaskPriority
    }

    private var subscriptions = [TaskSubscriptionKey: Subscription]()
    private var nextSubscriptionId = 0

    /// Returns `true` if the task was either cancelled, or was completed.
    private(set) var isDisposed = false

    /// Gets called when the task is either cancelled, or was completed.
    var onDisposed: (() -> Void)?

    var onCancelled: (() -> Void)?

    private var starter: ((Task) -> Void)?

    private var priority: TaskPriority = .normal {
        didSet {
            guard oldValue != priority else { return }
            operation?.queuePriority = priority.queuePriority
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

    weak var operation: Foundation.Operation? {
        didSet {
            operation?.queuePriority = priority.queuePriority
        }
    }

    /// Publishes the results of the task.
    var publisher: Publisher { Publisher(task: self) }

    /// Initializes the task with the `starter`.
    /// - parameter starter: The closure which gets called as soon as the first
    /// subscription is added to the task. Only gets called once and is immediatelly
    /// deallocated after it is called.
    init(starter: ((Task) -> Void)? = nil) {
        self.starter = starter
    }

    // MARK: - Managing Observers

    /// - notes: Returns `nil` if the task was disposed.
    private func subscribe(priority: TaskPriority = .normal, _ observer: @escaping (Event) -> Void) -> TaskSubscription? {
        guard !isDisposed else { return nil }

        nextSubscriptionId += 1
        let subscriptionKey = nextSubscriptionId
        let subscription = TaskSubscription(task: self, key: subscriptionKey)

        subscriptions[subscriptionKey] = Subscription(observer: observer, priority: priority)
        updatePriority()

        starter?(self)
        starter = nil

        // The task may have been completed synchronously by `starter`.
        guard !isDisposed else { return nil }

        return subscription
    }

    // MARK: - TaskSubscriptionDelegate

    fileprivate func setPriority(_ priority: TaskPriority, for key: TaskSubscriptionKey) {
        guard !isDisposed else { return }

        subscriptions[key]?.priority = priority
        updatePriority()
    }

    fileprivate func unsubsribe(key: TaskSubscriptionKey) {
        guard subscriptions.removeValue(forKey: key) != nil else { return } // Already unsubscribed from this task
        guard !isDisposed else { return }

        if subscriptions.isEmpty {
            terminate(reason: .cancelled)
        } else {
            updatePriority()
        }
    }

    // MARK: - Sending Events

    func send(value: Value, isCompleted: Bool = false) {
        send(event: .value(value, isCompleted: isCompleted))
    }

    func send(error: Error) {
        send(event: .error(error))
    }

    func send(progress: TaskProgress) {
        send(event: .progress(progress))
    }

    private func send(event: Event) {
        guard !isDisposed else { return }

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

        for context in subscriptions.values {
            context.observer(event)
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
            onCancelled?()
        }
        onDisposed?()
    }

    // MARK: - Priority

    private func updatePriority() {
        priority = subscriptions.values.map({ $0.priority }).max() ?? .normal
    }
}

// MARK: - Task (Publisher)

extension Task {
    /// Publishes the results of the task.
    struct Publisher {
        let task: Task

        /// Attaches the subscriber to the task.
        /// - notes: Returns `nil` if the task is already disposed.
        func subscribe(priority: TaskPriority = .normal, _ observer: @escaping (Event) -> Void) -> TaskSubscription? {
            task.subscribe(priority: priority, observer)
        }

        /// Attaches the subscriber to the task. Automatically forwards progress
        /// andd error events to the given task.
        /// - notes: Returns `nil` if the task is already disposed.
        func subscribe<NewValue>(_ task: Task<NewValue, Error>, onValue: @escaping (Value, Bool, Task<NewValue, Error>) -> Void) -> TaskSubscription? {
            return subscribe { [weak task] event in
                guard let task = task else { return }
                switch event {
                case let .value(value, isCompleted):
                    onValue(value, isCompleted, task)
                case let .progress(progress):
                    task.send(progress: progress)
                case let .error(error):
                    task.send(error: error)
                }
            }
        }
    }
}

struct TaskProgress: Hashable {
    let completed: Int64
    let total: Int64
}

typealias TaskPriority = ImageRequest.Priority // typealias will do for now

// MARK: - Task.Event {
extension Task {
    enum Event {
        case value(Value, isCompleted: Bool)
        case progress(TaskProgress)
        case error(Error)

        var isCompleted: Bool {
            switch self {
            case let .value(_, isCompleted): return isCompleted
            case .progress: return false
            case .error: return true
            }
        }
    }
}

extension Task.Event: Equatable where Value: Equatable, Error: Equatable {}

// MARK: - TaskSubscription

/// Represents a subscription to a task. The observer must retain a strong
/// reference to a subscription.
final class TaskSubscription {
    private let task: TaskSubscriptionDelegate
    private let key: TaskSubscriptionKey

    fileprivate init(task: TaskSubscriptionDelegate, key: TaskSubscriptionKey) {
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
        task.unsubsribe(key: key)
    }

    /// Updates the priority of the subscription. The priority of the task is
    /// calculated as the maximum priority out of all of its subscription. When
    /// the priority of the task is updated, the priority of a dependency also is.
    ///
    /// - note: The priority also automatically gets updated when the subscription
    /// is removed from the task.
    func setPriority(_ priority: TaskPriority) {
        task.setPriority(priority, for: key)
    }
}

private protocol TaskSubscriptionDelegate: AnyObject {
    func unsubsribe(key: TaskSubscriptionKey)
    func setPriority(_ priority: TaskPriority, for observer: TaskSubscriptionKey)
}

private typealias TaskSubscriptionKey = Int

// MARK: - TaskPool

/// Contains the tasks which haven't completed yet.
final class TaskPool<Value, Error> {
    private let isDeduplicationEnabled: Bool
    private var map = [AnyHashable: Task<Value, Error>]()

    init(_ isDeduplicationEnabled: Bool) {
        self.isDeduplicationEnabled = isDeduplicationEnabled
    }

    /// Creates a task with the given key. If there is an outstanding task with
    /// the given key in the pool, the existing task is returned. Tasks are
    /// automatically removed from the pool when they are disposed.
    func task(withKey key: AnyHashable, starter: @escaping (Task<Value, Error>) -> Void) -> Task<Value, Error> {
        task(withKey: key) {
            Task<Value, Error>(starter: starter)
        }
    }

    private func task(withKey key: AnyHashable, _ make: () -> Task<Value, Error>) -> Task<Value, Error> {
        guard isDeduplicationEnabled else {
            return make()
        }
        if let task = map[key] {
            return task
        }
        let task = make()
        map[key] = task
        task.onDisposed = { [weak self] in
            self?.map[key] = nil
        }
        return task
    }
}
