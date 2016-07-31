// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

extension Nuke.PromiseResolution {
    public var value: T? {
        if case let .fulfilled(val) = self { return val }
        return nil
    }
    
    public var error: ErrorProtocol? {
        if case let .rejected(err) = self { return err }
        return nil
    }
    
    public var isSuccess: Bool {
        return value != nil
    }
}
