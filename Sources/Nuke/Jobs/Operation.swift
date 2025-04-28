import Foundation

/// A simple job that represents an operation that executes the given closure
/// on a thread managed by Swift Concurrency.
final class Operation<Value: Sendable>: Job<Value> {
    // This needs to be replaced with typed throws as soon as Swift supports infrence for closures
    private let closure: @Sendable () -> Result<Value, ImageTask.Error>
    private let name: StaticString
    private var task: Task<Void, Never>?

    /// Initialize the task with the given closure to be executed in the background.
    init(name: StaticString = "Operation", closure: @Sendable @escaping () -> Result<Value, ImageTask.Error>) {
        self.name = name
        self.closure = closure
        super.init()
    }

    override func start() {
        task = Task.detached {
            let result = self.closure()
            await self.finish(with: result)
        }
    }

    // TODO: cleanup
    override func onCancel() {
        if let task {
            task.cancel()
        } else {
            super.onCancel()
        }
    }

    struct ProxySubscriber: JobSubscriber {
        let owner: (any JobOwner)?
        let completion: @ImagePipelineActor @Sendable (Result<Value, ImageTask.Error>) -> Void

        var priority: JobPriority { owner?.priority ?? .normal }

        func addSubscribedTasks(to output: inout [ImageTask]) {
            owner?.addSubscribedTasks(to: &output)
        }

        func receive(_ event: Job<Value>.Event) {
            switch event {
            case let .value(value, isCompleted):
                if isCompleted {
                    completion(.success(value))
                }
            case .progress:
                break
            case let .error(error):
                completion(.failure(error))
            }
        }
    }

    @discardableResult func receive(
        _ owner: (any JobOwner)? = nil,
        _ completion: @ImagePipelineActor @Sendable @escaping (Result<Value, ImageTask.Error>) -> Void
    ) -> JobSubscription? {
        subscribe(ProxySubscriber(owner: owner, completion: completion))
    }
}
