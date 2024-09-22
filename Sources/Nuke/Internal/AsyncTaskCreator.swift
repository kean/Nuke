import Foundation

/// AsyncTaskCreator creates Swift `Task` that
/// execute the underlying passed operation.
///
/// AsyncTaskCreator can be thought of as a builder
/// of Swift `Task` that could be used to
/// build custom tasks in different environments.
struct AsyncTaskCreator<Result: Sendable> {
    typealias Operation = @Sendable () async throws -> Result

    let _createTask: (_ operation: @escaping Operation) -> Task<Result, Error>

    func createTask(operation: @escaping Operation) -> Task<Result, Error> {
        _createTask(operation)
    }
}
