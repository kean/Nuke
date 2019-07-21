// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Represents a task with support for multiple observers, cancellation,
/// progress reporting, dependencies – everything that `ImagePipeline` needs.
///
/// Each `Task` has one or more subscriptions (`TaskSubscription`) which can
/// be used to later unsubscribe or change the priority of the subscription.
///
/// The job performed by the task is represented using `Task.Job`. The job has
/// built-in support for operations (`Foundation.Operation`) – it automatically
/// cancels them, updates the priority, etc. Most steps in the image pipeline are
/// represented using Operation to take advantage of these features.
///
/// - warning: Must be thread-confined, including jobs.
final class Task<Value, Error>: TaskSubscriptionDelegate {

    private struct SubscriptionContext {
        let observer: (Event) -> Void
        var priority: TaskPriority
    }

    private var subscriptions = [TaskSubscriptionKey: SubscriptionContext]()
    private var nextSubscriptionId = 0

    private enum State {
        case executing, failed, completed, cancelled
    }

    private var state: State = .executing

    /// Gets called when the task is either cancelled, or was completed.
    var onDisposed: (() -> Void)?

    /// Returns `true` if the task was either cancelled, or was completed.
    var isDisposed: Bool {
        return state != .executing
    }

    private lazy var job = Job(task: self)
    private var starter: ((Job) -> Void)?

    private var priority: TaskPriority = .normal {
        didSet {
            guard oldValue != priority else { return }
            job.operation?.queuePriority = priority.queuePriority
            job.dependency?.setPriority(priority)
        }
    }

    /// Initializes the task with the `starter`.
    /// - parameter starter: The closure which gets called as soon as the first
    /// subscription is added to the task. Only gets called once and is immediatelly
    /// deallocated after it is called.
    init(starter: @escaping (Job) -> Void) {
        self.starter = starter
    }

    // MARK: - Managing Observers

    /// - notes: Returns `nil` if the task was disposed.
    func subscribe(priority: TaskPriority = .normal, _ observer: @escaping (Event) -> Void) -> TaskSubscription? {
        guard !isDisposed else { return nil }

        nextSubscriptionId += 1
        let subscriptionKey = nextSubscriptionId
        let subscription = TaskSubscription(task: self, key: subscriptionKey)

        subscriptions[subscriptionKey] = SubscriptionContext(observer: observer, priority: priority)
        updatePriority()

        starter?(job)
        starter = nil

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
            transition(to: .cancelled)
        } else {
            updatePriority()
        }
    }

    // MARK: - Sending Events

    private func send(event: Event) {
        guard !isDisposed else { return }

        switch event {
        case let .value(_, isCompleted):
            if isCompleted {
                transition(to: .completed)
            }
        case .progress:
            break // Simply send the event
        case .error:
            transition(to: .failed)
        }

        for context in subscriptions.values {
            context.observer(event)
        }
    }

    // MARK: - State Transition

    private func transition(to state: State) {
        guard !isDisposed else { return }

        self.state = state
        if state == .cancelled {
            job.cancel()
        }
        onDisposed?() // All states except for `executing` are final
    }

    // MARK: - Priority

    private func updatePriority() {
        priority = subscriptions.values.map({ $0.priority }).max() ?? .normal
    }
}

extension Task {
    func map<NewValue>(_ job: Task<NewValue, Error>.Job, _ transform: @escaping (Value, Bool, Task<NewValue, Error>.Job) -> Void) -> TaskSubscription? {
        return subscribe { [weak job] event in
            guard let job = job else { return }
            switch event {
            case let .value(value, isCompleted):
                transform(value, isCompleted, job)
            case let .progress(progress):
                job.send(progress: progress)
            case let .error(error):
                job.send(error: error)
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

// MARK: - Task.Job

extension Task {
    final class Job {
        private weak var task: Task?

        var onCancelled: (() -> Void)?

        var isDisposed: Bool {
            return task?.isDisposed ?? true
        }

        weak var operation: Foundation.Operation? {
            didSet {
                guard let task = task else { return }
                operation?.queuePriority = task.priority.queuePriority
            }
        }

        /// Each task might have a dependency. The task automatically unsubscribes
        /// from the dependency when it gets cancelled, and also updates the
        /// priority of the subscription to the dependency when its own
        /// priority is updated.
        var dependency: TaskSubscription? {
            didSet {
                guard let task = task else { return }
                dependency?.setPriority(task.priority)
            }
        }

        fileprivate init(task: Task) {
            self.task = task
        }

        func send(value: Value, isCompleted: Bool = false) {
            task?.send(event: .value(value, isCompleted: isCompleted))
        }

        func send(error: Error) {
            task?.send(event: .error(error))
        }

        func send(progress: TaskProgress) {
            task?.send(event: .progress(progress))
        }

        fileprivate func cancel() {
            operation?.cancel()
            dependency?.unsubscribe()
            onCancelled?()
        }
    }
}

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
    /// cancelled along with its job and its dependencies. The cancelled task is
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

private protocol TaskSubscriptionDelegate: class {
    func unsubsribe(key: TaskSubscriptionKey)
    func setPriority(_ priority: TaskPriority, for observer: TaskSubscriptionKey)
}

private typealias TaskSubscriptionKey = Int

// MARK: - TaskPool

/// Pool of outstanding tasks.
final class TaskPool<Value, Error> {
    private let isDeduplicationEnabled: Bool
    private var map = [AnyHashable: Task<Value, Error>]()

    init(isDeduplicationEnabled: Bool) {
        self.isDeduplicationEnabled = isDeduplicationEnabled
    }

    func task(withKey key: AnyHashable, _ starter: @escaping (Task<Value, Error>.Job) -> Void) -> Task<Value, Error> {
        return task(withKey: key) { Task<Value, Error>(starter: starter) }
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
