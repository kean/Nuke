// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A one-shot task for performing a single () -> T function.
final class OperationTask<T: Sendable>: AsyncTask<T, Swift.Error> {
    private let pipeline: ImagePipeline
    private let queue: OperationQueue
    private let process: () throws -> T

    init(_ pipeline: ImagePipeline, _ queue: OperationQueue, _ process: @escaping () throws -> T) {
        self.pipeline = pipeline
        self.queue = queue
        self.process = process
    }

    override func start() {
        operation = queue.add { [weak self] in
            guard let self = self else { return }
            let result = Result(catching: { try self.process() })
            self.pipeline.queue.async {
                switch result {
                case .success(let value):
                    self.send(value: value, isCompleted: true)
                case .failure(let error):
                    self.send(error: error)
                }
            }
        }
    }

    struct Error: Swift.Error {}
}
