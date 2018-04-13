// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

extension Nuke.ImageRequest {
    func mutated(_ closure: (inout ImageRequest) -> Void) -> ImageRequest {
        var request = self
        closure(&request)
        return request
    }
}
