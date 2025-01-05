// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

extension OperationQueue {
    /// Adds simple `BlockOperation`.
    func add(_ closure: @Sendable @escaping () -> Void) -> BlockOperation {
        let operation = BlockOperation(block: closure)
        addOperation(operation)
        return operation
    }
}
