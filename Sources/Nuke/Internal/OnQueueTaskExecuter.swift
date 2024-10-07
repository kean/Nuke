import Foundation

/// OnQueueTaskExecuter is a custom `TaskExecutor` that
/// runs jobs on a specific `DispatchQueue`.
@available(iOSApplicationExtension 18.0, *)
final class OnQueueTaskExecuter: TaskExecutor {
    let queue: DispatchQueue
    
    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func enqueue(_ job: UnownedJob) {
        queue.async {
            job.runSynchronously(on: self.asUnownedTaskExecutor())
        }
    }

    func asUnownedTaskExecutor() -> UnownedTaskExecutor {
        UnownedTaskExecutor(ordinary: self)
    }
}
