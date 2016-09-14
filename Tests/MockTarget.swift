// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockTarget: Target {
    var handler: Manager.Handler?
    
    func handle(response: Response, isFromMemoryCache: Bool) {
        handler?(response, isFromMemoryCache)
    }
}
