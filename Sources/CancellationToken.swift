// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: CancellationToken

public class CancellationTokenSource {
    private(set) var isCancelling = false
    private var observers = [() -> Void]()
    private let queue = DispatchQueue(label: "\(domain).CancellationToken")
    
    public var token: CancellationToken {
        return CancellationToken(source: self)
    }
    
    public init() {}
    
    private func register(_ closure: () -> Void) {
        queue.async {
            if self.isCancelling {
                closure()
            } else {
                self.observers.append(closure)
            }
        }
    }
    
    public func cancel() {
        queue.async {
            if !self.isCancelling {
                self.isCancelling = true
                self.observers.forEach { $0() }
                self.observers.removeAll()
            }
        }
    }
}

public struct CancellationToken {
    private let source: CancellationTokenSource
    private init(source: CancellationTokenSource) {
        self.source = source
    }
    
    public var isCancelling: Bool {
        return source.isCancelling
    }
    
    public func register(closure: () -> Void) {
        source.register(closure)
    }
}
