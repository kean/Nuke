// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockTarget: Target {
    var handler: ((Resolution<Image>, Bool) -> Void)?
    
    func handle(response: Resolution<Image>, isFromMemoryCache: Bool) {
        handler?(response, isFromMemoryCache)
    }
}
