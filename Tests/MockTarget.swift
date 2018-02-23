// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockTarget: Target {
    var handler: Manager.Handler?
    
    func handle(response: Result<Image>, isFromMemoryCache: Bool) {
        handler?(response, isFromMemoryCache)
    }
}
