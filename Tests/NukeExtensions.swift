// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

extension ImageRequest {
    func mutated(_ closure: (inout ImageRequest) -> Void) -> ImageRequest {
        var request = self
        closure(&request)
        return request
    }
}

#if os(macOS)
import Cocoa
typealias _ImageView = NSImageView
#else
import UIKit
typealias _ImageView = UIImageView
#endif
