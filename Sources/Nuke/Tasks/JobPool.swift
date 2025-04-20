import Foundation

@ImagePipelineActor
final class JobPool<Key: Hashable, Value: Sendable> {
    private let isCoalescingEnabled: Bool
    private var map = [Key: Job<Value>]()

    nonisolated init(_ isCoalescingEnabled: Bool) {
        self.isCoalescingEnabled = isCoalescingEnabled
    }

    /// Creates a task with the given key. If there is an outstanding task with
    /// the given key in the pool, the existing task is returned. Tasks are
    /// automatically removed from the pool when they are disposed.
    func task(for key: @autoclosure () -> Key, _ make: () -> Job<Value>) -> Job<Value> {
        guard isCoalescingEnabled else {
            return make()
        }
        let key = key()
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
