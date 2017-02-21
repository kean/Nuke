// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

extension Nuke.Request {
    func mutated(_ closure: (inout Request) -> Void) -> Request {
        var request = self
        closure(&request)
        return request
    }
}
